# Emirates staging UI verification — 9 September 2026

## Confirmed booking

- Account: `sini+123@nuflights.com`
- UI organisation: Darsana Tours and Travels (`T-DTT`, observed on NDC requests)
- Order group: `N-167359TNB`
- NDC order: `EK176SQ2B71A3`
- Airline booking reference: `BZIH3F`
- Passenger: synthetic `TEST PASSENGER`, one adult
- Flight: EK005, DXB–LHR, 23 September 2026, 15:45–20:15 local times
- Fare: Economy Flex, QAR 2,350
- Status: Booked; unpaid and not ticketed

Booking was submitted through the UI, then opened through **View Order**. No API call was used to create this booking. One **Refresh Order** was also performed. See `reports/ui-booking-receipt.json` and `reports/ui-booking-confirmed-20260909.png`.

## Fixed configuration issue

The Emirates API collection previously sent `T-213ek`, while this user's UI session sends `T-DTT`. After updating the Staging header value to `T-DTT`, Login, Air Shopping and Offer Price passed all eight API assertions. This account's earlier subscription error was resolved by using its verified organisation; do not reuse that setting for unrelated accounts without checking their authorised organisation.

## Remaining observations for the application team

1. **TTL warning survives a refresh.** After successful order creation, the UI says to retrieve the order for its updated TTL. After refreshing, `NFE-NDC-TTL-INCORRECT` remains and the UI still cannot display the updated TTL. Investigate the provider OrderRetrieve mapping and TTL parsing/time-zone handling for the order above. Booking success is independently confirmed; TTL correctness is not.
2. **Passenger date-entry inconsistency.** Filling `09/09/2031` into Passport Expiry and `13/02/1990` into DOB, whose placeholders say `DD/MM/YYYY`, resulted in cleared/invalid values. Selecting the same dates through the calendar worked. Reproduce with keyboard input and check parsing/blur handling. The regression uses calendar controls.
3. **Disabled booking control is CSS-only.** During incomplete passenger entry the booking button had `btn--disabled` but no native `disabled` attribute; a wrapper intercepted clicks. Prefer native disabled/ARIA state so keyboard users and automation receive the correct state. The regression checks the class as well as using ordinary clicks; it does not force-click through the wrapper.

## Regression scope

Final verification on 9 September: **2/2 Playwright UI tests passed** (58.8 seconds), **8/8 API assertions passed** across Login, Air Shopping and Offer Price, and **9/9 offline collection checks passed**. The browser report is `reports/ui-report/index.html`; the API report is `reports/ui-org-api-verified-20260909.json`.

The default UI suite searches and prices an Emirates flight, validates synthetic passenger/calendar input through the ancillary step, and checks the previously created order. It does not submit another order or issue a ticket. Full creation is explicitly enabled using `UI_CREATE_BOOKING=1`; retries remain off to prevent duplicates. The full issuance/payment/reshop API workflow was not executed during this UI task.
