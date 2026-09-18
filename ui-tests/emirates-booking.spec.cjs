const { test, expect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const base = 'https://workbench.staging.llc.nuflights.com';
const receiptPath = path.join(root, 'reports/ui-booking-receipt.json');
const createBooking = process.env.UI_CREATE_BOOKING === '1';
const env = { ...process.env };
const envPath = path.join(root, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^([A-Z_]+)=(.*)$/);
    if (match) env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
}
function departure() {
  const date = new Date();
  date.setDate(date.getDate() + 14);
  return `${String(date.getDate()).padStart(2,'0')}/${String(date.getMonth()+1).padStart(2,'0')}/${date.getFullYear()}`;
}
async function login(page, context) {
  if (!env.TEST_USER_EMAIL || !env.TEST_USER_PASSWORD) throw new Error('Configure TEST_USER_EMAIL and TEST_USER_PASSWORD in .env');
  await page.goto(base + '/search');
  await page.getByPlaceholder('Email', { exact: true }).fill(env.TEST_USER_EMAIL);
  await page.getByPlaceholder('Password', { exact: true }).fill(env.TEST_USER_PASSWORD);
  await page.getByRole('button', { name: /^sign in$/i }).click();
  await page.waitForURL(url => url.hostname === 'home.staging.llc.nuflights.com');
  await page.getByRole('button', { name: /Travel Workbench/i }).click();
  const workbench = page;
  await workbench.waitForURL(base + '/search');
  await expect(workbench.getByText('Darsana Tours and Travels', { exact: true })).toBeVisible();
  return workbench;
}
async function graphql(page, field, action) {
  const responsePromise = page.waitForResponse(response => {
    if (!response.url().includes('/ndc-connect') || response.request().method() !== 'POST') return false;
    const payload = response.request().postDataJSON();
    return (payload?.query || '').includes(field + '(');
  }, { timeout: 150000 });
  await action();
  const response = await responsePromise;
  expect(response.status(), field + ' HTTP status').toBe(200);
  const org = response.request().headers()['x-nf-active-org-short-code'];
  expect(org, 'Organisation resolved by the logged-in UI').toBe('T-DTT');
  const body = await response.json();
  expect(body.errors || [], field + ': ' + JSON.stringify(body.errors || [])).toEqual([]);
  const raw = body.data?.[field];
  const result = Array.isArray(raw) ? raw[0] : raw;
  expect(result, field + ' result').toBeTruthy();
  const businessErrors = Array.isArray(result.error) ? result.error : result.error ? [result.error] : [];
  const blockingErrors = businessErrors.filter(error => !(
    ['iataOrderCreate', 'iataOrderRetrieve'].includes(field) &&
    error.type === 'Warning' && error.code === 'NFE-NDC-TTL-INCORRECT'
  ));
  expect(blockingErrors, JSON.stringify(businessErrors)).toEqual([]);
  expect(result.response, field + ' response').toBeTruthy();
  return result;
}
async function calendar(page, index, year, month, day) {
  await page.getByPlaceholder('DD/MM/YYYY', { exact: true }).nth(index).click();
  await page.locator('.react-datepicker__year-select').selectOption(String(year));
  await page.locator('.react-datepicker__month-select').selectOption({ label: month });
  await page.locator(`.react-datepicker__day--${String(day).padStart(3,'0')}:not(.react-datepicker__day--outside-month)`).click();
}
async function passenger(page) {
  await page.getByPlaceholder('Passport Number', { exact: true }).fill('123456789');
  await page.locator('select[name=nationality]').selectOption({ label: 'GREAT_BRITAIN (GB)' });
  await calendar(page, 0, new Date().getFullYear() + 5, 'September', 9);
  await page.locator('select[name=title]').selectOption({ label: 'MR' });
  await page.locator('select[name=gender]').selectOption({ label: 'Male' });
  await calendar(page, 1, 1990, 'February', 13);
  await page.getByPlaceholder('First Name', { exact: true }).fill('TEST');
  await page.getByPlaceholder('Last Name', { exact: true }).fill('PASSENGER');
  await page.getByPlaceholder('ISD', { exact: true }).fill('44');
  await page.getByPlaceholder('Number', { exact: true }).fill('7700900123');
  await page.getByPlaceholder('Email Address', { exact: true }).fill('emirates-ui-test@example.com');
  await expect(page.getByText('Invalid Date', { exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Next', exact: true }).click();
  await expect(page).toHaveURL(/\/booking\/seat-map$/);
  await page.getByRole('button', { name: 'Next', exact: true }).click();
  await expect(page).toHaveURL(/\/booking\/ancillaries$/);
  await expect(page.getByRole('button', { name: 'Proceed & Book', exact: true })).not.toHaveClass(/btn--disabled/);
}
test('Emirates UI search, pricing and valid passenger flow', async ({ page, context }, testInfo) => {
  const ui = await login(page, context);
  await ui.getByText('Please Select', { exact: true }).click();
  await ui.getByText('Emirates Airlines', { exact: true }).click();
  // Airline selection is multi-select: close the overlay before airport entry.
  await ui.getByRole('heading', { name: 'Search Flights', exact: true }).click();
  await ui.locator('input[name=departure]').fill('DXB');
  await ui.getByText('DXB - Dubai International Airport, Dubai, AE', { exact: true }).click();
  await ui.locator('input[name=arrival]').fill('LHR');
  await ui.getByText('LHR - London Heathrow Airport, London, GB', { exact: true }).click();
  await ui.getByPlaceholder('DD/MM/YYYY', { exact: true }).fill(departure());
  await ui.getByRole('heading', { name: 'Search Flights', exact: true }).click();
  const shopping = await graphql(ui, 'iataAirShopping', () => ui.getByRole('button', { name: 'Search Flights', exact: true }).click());
  const offers = shopping.response.offersGroup?.carrierOffers?.flatMap(carrier => carrier.offer || []) || [];
  expect(offers.length, 'Emirates offers').toBeGreaterThan(0);
  expect(offers.every(offer => offer.ownerCode === 'EK')).toBe(true);
  const priced = await graphql(ui, 'iataOfferPrice', () => ui.locator('p.time').first().click());
  expect(priced.response.pricedOffer.ownerCode).toBe('EK');
  await ui.getByRole('button', { name: 'Continue', exact: true }).click();
  await expect(ui).toHaveURL(/\/booking\/passengers$/);
  await passenger(ui);
  await testInfo.attach('ready-to-book', { body: await ui.screenshot({ fullPage: true }), contentType: 'image/png' });
  // Explicit opt-in avoids duplicate bookings during ordinary regression runs.
  if (createBooking) {
    const created = await graphql(ui, 'iataOrderCreate', () => ui.getByRole('button', { name: 'Proceed & Book', exact: true }).click());
    const order = Array.isArray(created.response.order) ? created.response.order[0] : created.response.order;
    expect(order?.orderId).toBeTruthy();
    await expect(ui.getByText('Success', { exact: true })).toBeVisible();
    await ui.getByRole('button', { name: 'View Order', exact: true }).click();
    await expect(ui).toHaveURL(/\/retreive-orders\/view-order-details\//);
    await expect(ui.getByText('Booked', { exact: true }).first()).toBeVisible();
    fs.writeFileSync(receiptPath, JSON.stringify({ url: ui.url(), nfOrderId: created.augmentationPoint.common.nfOrderId, orderId: order.orderId, passenger: 'PASSENGER/TEST MR', status: 'Booked', createdAt: new Date().toISOString() }, null, 2));
  }
});
test('existing Emirates UI order retains passenger, route and booked status', async ({ page, context }) => {
  test.skip(!fs.existsSync(receiptPath), 'No local booking receipt; run with UI_CREATE_BOOKING=1 first');
  const receipt = JSON.parse(fs.readFileSync(receiptPath, 'utf8'));
  const target = new URL(receipt.url);
  expect(target.origin).toBe(base);
  const ui = await login(page, context);
  await ui.goto(target.href);
  await expect(ui.getByText('Booked', { exact: true }).first()).toBeVisible();
  await expect(ui.getByText(receipt.orderId, { exact: true })).toBeVisible();
  await expect(ui.getByRole('row').filter({ hasText: /PASSENGER/ }).filter({ hasText: /TEST/ }).filter({ hasText: /EMIRATES-UI-TEST@EXAMPLE.COM/i })).toBeVisible();
  await expect(ui.getByText('DXB - LHR', { exact: true })).toBeVisible();
  await expect(ui.getByRole('button', { name: 'Issue', exact: true })).toBeVisible();
});
