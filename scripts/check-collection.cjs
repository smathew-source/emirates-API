const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
function block(file, name) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const match = source.match(new RegExp('^' + name + ' \\{\\r?\\n([\\s\\S]*?)^\\}', 'm'));
  assert(match, `${file}: ${name} is missing`);
  return match[1];
}
function context(processEnv = {}, env = {}) {
  const runtime = {};
  return {
    runtime, env,
    bru: {
      getProcessEnv: name => processEnv[name],
      getEnvVar: name => env[name],
      getVar: name => Object.hasOwn(runtime, name) ? runtime[name] : env[name],
      setVar: (name, value) => { runtime[name] = value; },
      setEnvVar: (name, value) => { env[name] = value; },
      deleteVar: name => { delete runtime[name]; },
      deleteEnvVar: name => { delete env[name]; }
    }
  };
}
function run(file, name, ctx) { vm.runInNewContext(block(file, name), ctx); }
let checks = 0;
function check(name, callback) { callback(); checks++; console.log(`PASS ${name}`); }
const login = 'Auth/Login.bru';
const shopping = 'Flight Search/Air Shopping DXB to LHR.bru';
check('missing credentials block Login and clear stale authentication', () => {
  const ctx = context({}, { authToken: 'old', ndcAuthorization: 'old' });
  assert.throws(() => run(login, 'script:pre-request', ctx), /credentials are missing/);
  assert.equal(ctx.bru.getVar('ndcAuthorization'), '');
});
check('dotenv credentials map to request variables and matching identity enables authentication', () => {
  const ctx = context({ TEST_USER_EMAIL: 'test@example.test', TEST_USER_PASSWORD: 'fixture-password' });
  run(login, 'script:pre-request', ctx);
  assert.equal(ctx.runtime.testUserEmail, 'test@example.test');
  assert.equal(ctx.runtime.testUserPassword, 'fixture-password');
  ctx.res = { body: { data: { login: { token: 'fixture-token', user: { email: 'test@example.test' } } } } };
  run(login, 'script:post-response', ctx);
  assert.equal(ctx.runtime.ndcAuthorization, 'fixture-token');
});
check('token without matching user never enables downstream authentication', () => {
  for (const user of [null, { email: 'wrong@example.test' }]) {
    const ctx = context({ TEST_USER_EMAIL: 'test@example.test', TEST_USER_PASSWORD: 'fixture-password' });
    run(login, 'script:pre-request', ctx);
    ctx.res = { body: { data: { login: { token: 'fixture-token', user } } } };
    run(login, 'script:post-response', ctx);
    assert.equal(ctx.runtime.ndcAuthorization, '');
  }
});
check('failed shopping clears old selected and priced offers without a null-data exception', () => {
  const ctx = context({}, { ndcAuthorization: 'fixture-token', selectedOfferId: 'old', pricedOfferId: 'old' });
  run(shopping, 'script:pre-request', ctx);
  ctx.res = { body: { data: null, errors: [{ message: 'Subscription unavailable' }] } };
  run(shopping, 'script:post-response', ctx);
  assert.equal(ctx.bru.getVar('selectedOfferId'), '');
  assert.equal(ctx.bru.getVar('pricedOfferId'), '');
});
check('empty shopping responses do not crash or store offers', () => {
  const ctx = context({}, { ndcAuthorization: 'fixture-token' });
  run(shopping, 'script:pre-request', ctx);
  ctx.res = { body: { data: { iataAirShopping: [{ response: {} }] } } };
  run(shopping, 'script:post-response', ctx);
  assert.equal(ctx.bru.getVar('selectedOfferId'), '');
});
check('pricing without shopping is blocked and stale priced data is cleared', () => {
  const ctx = context({}, { pricedOfferId: 'old' });
  assert.throws(() => run('Flight Search/Offer Price.bru', 'script:pre-request', ctx), /successful Air Shopping/);
  assert.equal(ctx.bru.getVar('pricedOfferId'), '');
});
check('order creation without successful pricing is blocked', () => {
  assert.throws(() => run('Flight Search/Order Create.bru', 'script:pre-request', context()), /successful Offer Price/);
});
check('successful shopping stores fresh identifiers and enables pricing', () => {
  const ctx = context({}, { ndcAuthorization: 'fixture-token' });
  run(shopping, 'script:pre-request', ctx);
  ctx.req = { body: { variables: { rq: { request: { flightRequest: { flightRequestOriginDestinationsCriteria: {
    originDestCriteria: [{ originDepCriteria: { iataLocationCode: 'DXB', date: '2030-01-01' }, destArrivalCriteria: { iataLocationCode: 'LHR' }, cabinType: [{ cabinTypeCode: '5' }] }]
  } } } } } } };
  ctx.res = { body: { data: { iataAirShopping: [{
    payloadAttributes: { trxId: 'fresh-trx' },
    augmentationPoint: { common: { nfSubscriptionId: 'fresh-sub' }, provider: { nfShoppingResponseId: 'fresh-shopping' } },
    error: null,
    response: { offersGroup: { carrierOffers: [{ offer: [{ offerId: 'fresh-offer', ownerCode: 'EK', offerItem: [{ offerItemId: 'fresh-item', service: [{ paxRefId: ['T1'] }] }] }] }] } }
  }] } } };
  run(shopping, 'script:post-response', ctx);
  assert.equal(ctx.runtime.selectedOfferId, 'fresh-offer');
  assert.equal(ctx.runtime.selectedNfSubscriptionId, 'fresh-sub');
  run('Flight Search/Offer Price.bru', 'script:pre-request', ctx);
});
function checkChangeErrors(errors) {
  let executed = false;
  run('Order Servicing/Order Change Confirm.bru', 'tests', {
    res: { body: { data: { iataOrderChange: { error: errors } } } },
    test: (name, callback) => {
      if (name === 'OrderChange confirm has no business errors') {
        executed = true;
        callback();
      }
    },
    expect: (actual, message) => ({ to: { equal: expected => assert.equal(actual, expected, message) } })
  });
  assert(executed, 'Business-error assertion must run');
}
const scheduleWarnings = ['Departure', 'Arrival'].map(kind => ({
  code: null, descText: `None - ${kind} Time changed for EK5 2026-10-07 DXBLHR`,
  typeCode: 'Warning', statusText: null
}));
check('OrderChange accepts the two schedule warnings reported in the failed run', () => {
  checkChangeErrors(scheduleWarnings);
  checkChangeErrors([...scheduleWarnings, { code: 'NFE-NDC-TTL-INCORRECT', typeCode: 'Warning' }]);
  checkChangeErrors(null);
});
check('OrderChange still rejects errors, unknown warnings and missing severity', () => {
  for (const error of [
    { ...scheduleWarnings[0], typeCode: 'Error' },
    { ...scheduleWarnings[0], typeCode: null },
    { code: 'OTHER', descText: 'Unexpected warning', typeCode: 'Warning' },
    { code: 'NFE-NDC-TTL-INCORRECT', typeCode: 'Error' }
  ]) assert.throws(() => checkChangeErrors([...scheduleWarnings, error]), assert.AssertionError);
});
check('all collection scripts compile', () => {
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith('.') || entry.name === 'reports' || entry.name === 'node_modules') continue;
      const target = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(target);
      else if (entry.name.endsWith('.bru')) {
        const text = fs.readFileSync(target, 'utf8');
        for (const match of text.matchAll(/^(?:script:pre-request|script:post-response|tests) \{\r?\n([\s\S]*?)^\}/gm)) {
          new vm.Script(match[1], { filename: target });
        }
      }
    }
  }
  walk(root);
});
console.log(`${checks} offline checks passed.`);
