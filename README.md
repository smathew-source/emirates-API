# Emirates API Bruno Collection

Bruno collection for the Emirates staging NDC workflow from authentication through order reshop.

## Environment

Use the `Staging` environment. Login maps `TEST_USER_EMAIL` and `TEST_USER_PASSWORD` from the collection-root `.env` into request variables. Bruno CLI loads `.env` automatically; it does not automatically load `.env.local`. The fallback is the Staging `testUserEmail` and secret `testUserPassword`.

- `apiBaseUrl`
- `authToken`
- `testUserEmail`
- `testUserPassword`

`apiBaseUrl` is set to `https://api.staging.nuflights.com/ndc-connect`. UI login uses `coreGraphqlUrl`, set to `https://api.staging.nuflights.com/core/graphql`.

Both `.env` and `.env.local` are ignored by git. Keep Bruno collection and environment files free of plaintext passwords. Keep the selected account and its password paired; a successful Login identity test confirms the actual returned email.

Run the collection from this directory:

```powershell
bru run --env Staging --bail --reporter-json reports/latest.json --reporter-skip-all-headers --reporter-skip-body
```

Run offline regression checks without calling the API:

```powershell
node scripts/check-collection.cjs
```

## Current verified result — 9 September 2026

UI login for `sini+123@nuflights.com` resolves **Darsana Tours and Travels**, and the observed UI shopping/pricing/create requests send organisation **`T-DTT`**. Staging now uses this verified code. This corrects the subscription failure previously seen with `T-213ek`; no backend subscription change was required for this account.

API verification: **3/3 requests, 8/8 tests passed** for Login, Air Shopping and Offer Price. Report: `reports/ui-org-api-verified-20260909.json`. This verification does not issue tickets or create a second order.

UI booking: **N-167359TNB**, Emirates reference **BZIH3F**, NDC order **EK176SQ2B71A3**. Synthetic passenger **TEST PASSENGER**, EK005, DXB to LHR, 23 September 2026, Economy Flex, **QAR 2,350**. Status verified as **Booked**; payment is pending and no ticket was issued. The existing order still reports `NFE-NDC-TTL-INCORRECT` after one UI refresh; updated ticketing time limit remains a backend/provider follow-up.

### UI regression tests

```powershell
npm ci
npm run test:ui
```

Requires Chrome and the same local `.env` credentials. Default execution checks UI login, the verified organisation header, Emirates search results, pricing, valid passenger/date entry, and retrieves the existing order from `reports/ui-booking-receipt.json`. It does not create another order. If there is no local receipt, the existing-order test is explicitly skipped. HTML report: `reports/ui-report/index.html`.

To deliberately create a new staging test booking through the full UI flow:

```powershell
$env:UI_CREATE_BOOKING = '1'
npm run test:ui
Remove-Item Env:UI_CREATE_BOOKING
```

Booking creation has no automatic retries. It uses synthetic passenger/contact details and stops at **Booked**, before payment/ticketing. The new receipt replaces the local verification target. Screenshots are local; traces/video are disabled to avoid recording login credentials.

The airline selector remains open after selection and must be closed before entering airports. Passenger date fields use calendar controls; filling slash-formatted dates directly was rejected as `Invalid Date`. The tests use the observed date-picker controls and wait for application state/API responses rather than fixed sleep intervals.

## Historical result — 8 September 2026

Account: `sini+123@nuflights.com`. Login passes both token and identity tests. Air Shopping fails its three tests with the same backend error: `Invalid data or state: An 'active' content subscription to the provider with the given airlineDesigCode was not found.` The request uses staging, organisation `T-213ek`, and airline `EK`.

Result: **2/5 tests passed; 1/2 requests passed**. Fail-fast execution stopped before Offer Price and all booking, ticketing, payment and servicing requests. Report: `reports/fix-verified-current.json`. Earlier successful reports below do not describe this account's current access.

Collection fixes: dotenv credential mapping, clearing stale authentication, publishing a token only for the intended returned user, clearing selected/priced offer state before upstream retries, prerequisite checks before pricing/creation, and explicit GraphQL error messages instead of null-data exceptions. Offline checks cover these cases and successful shopping state propagation.

### Earlier investigation (resolved by UI organisation verification)

Verify that this account can use organisation `T-213ek` and that the organisation has an active Emirates (`EK`) content subscription in staging. Check the provider mapping and any required shared-subscription relationship. If the account belongs to a different authorised organisation, use its verified organisation code; do not substitute a guessed code or a subscription identifier from an old run. Re-run the fail-fast command after the mapping is corrected. Subsequent workflow behaviour remains unverified until shopping succeeds.

## Workflow

Run requests in this order:

1. Login (Core GraphQL)
2. Air Shopping DXB to LHR
3. Offer Price
4. Order Create
5. Order Retrieve Before Issue
6. Issue Ticket
7. Record Customer Payment
8. Order Retrieve Before Change
9. Order Reshop Change Search
10. Order Change Confirm
11. Issue Ticket After Change

The collection uses organisation `T-DTT` and airline code `EK` with the Core GraphQL login workflow, matching the UI organisation observed for the configured Sini account on 9 September. Other accounts may require a different verified organisation.
State-changing requests create and ticket staging bookings. Use fail-fast execution to prevent stale identifiers from reaching later requests.

Travel dates are generated by `collection.bru` for every run: the original booking date is the run date plus 14 calendar days and the reshop date is the run date plus 28 calendar days.

## Test coverage

The request files contain assertions for:

- successful Core GraphQL authentication
- a non-empty Emirates shopping response and valid first offer
- successful offer pricing and a valid priced offer
- successful order creation with ticketable order details
- retrieval of the newly created order
- ticket issuance and returned ticket document
- recording customer payment
- retrieval of the ticketed order before a change
- successful reshop response containing change offers
- successful change confirmation and ticket issuance for the changed itinerary

Each dependent request has a pre-request check for identifiers produced by the preceding request. This prevents later requests from running with empty or stale order data.

## Earlier recorded staging result — 8 September 2026

Full fail-fast workflow: **11 requests passed, 36/36 tests passed**, including ticket issuance after the itinerary change. Reports: `reports/fixed-20260908.json` and `reports/fixed-20260908.xml`.

The staging organisation was corrected to `T-213ek` to match the active organisation resolved for the local test account. Change confirmation now treats `NFE-NDC-TTL-INCORRECT` as non-blocking only when its type is `Warning`; all other errors still fail, and confirmed booking details remain validated. The warning advises retrieving the order again for the updated ticket time limit.

## Historical staging result — 11 August 2026

Run with the locally configured Jeet test account and Core GraphQL login:

| Request | Result | Assertions |
| --- | --- | ---: |
| Login | Passed | 1 passed |
| Air Shopping DXB to LHR | Passed | 3 passed |
| Offer Price | Failed: `SharedSubscription matching query does not exist.` | 3 failed |
| Order Create | Failed: subscription ID is empty because Offer Price failed | 3 failed |
| Retrieve, ticketing, payment and reshop | Blocked because no order was created | Not executed |

Historical total: **4 passed and 6 failed assertions**. The first blocker at that time was the missing staging shared-subscription mapping between organisation `T-DTT` and the Emirates provider subscription.

