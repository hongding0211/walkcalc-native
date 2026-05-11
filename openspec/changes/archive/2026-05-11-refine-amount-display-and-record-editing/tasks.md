## 1. Money Display Rules

- [x] 1.1 Update compact money formatting so values below 100,000 major units render exactly with two decimal places.
- [x] 1.2 Add a shared exact signed-money display path for summary/detail balances without disrupting compact row callers.
- [x] 1.3 Use exact signed money on the home Total balance card, group My balance card, and member balance detail header.
- [x] 1.4 Keep compact signed money on dense group, balance preview, record, and settlement rows, using the raised threshold.
- [x] 1.5 Ensure member balance detail renders zero balances with primary detail amount emphasis rather than muted zero styling.

## 2. Record Editor Behavior

- [x] 2.1 Show the delete action for existing records immediately in idle viewing state.
- [x] 2.2 Keep top save/cancel actions hidden for idle existing records and visible only for new expense or existing-record edit mode.
- [x] 2.3 Make delete confirmation available without sending an update request or requiring edit intent.
- [x] 2.4 Make cancel from existing-record edit mode discard local draft changes, send no update request, and close the editor sheet.
- [x] 2.5 Preserve new-expense cancel/save behavior.

## 3. Search Behavior

- [x] 3.1 Remove the home screen `.searchable` UI and debounce search refresh flow.
- [x] 3.2 Keep group detail record search available after touching shared row or toolbar code.

## 4. Verification

- [x] 4.1 Verify 1,000 and 10,000-range amounts are exact while 100,000+ dense-row values may compact.
- [x] 4.2 Verify summary/detail balance surfaces show exact values and scale cleanly for long amounts.
- [x] 4.3 Verify existing-record open, delete confirmation, cancel-close, save-close, and no-update-on-cancel behavior.
- [x] 4.4 Run the relevant Swift build/tests and a simulator E2E smoke check for this app.

## 5. Follow-up Visual Polish

- [x] 5.1 Keep the edge-case overflowing summary amount as a simple truncated/scaled label without reveal or copy interactions.
- [x] 5.2 Prevent dense group, balance, record, and settlement row amounts from being compressed into an unreadable ellipsis.
- [x] 5.3 Re-run simulator E2E on the edge fixture to confirm summary truncation and row amount visibility.
- [x] 5.4 Re-run simulator E2E on the richer stress fixture for overall visual review.
