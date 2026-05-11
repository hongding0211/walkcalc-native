## Context

The app currently routes most signed money labels through `signedMoney`, which in turn always uses `Money.compactDisplay`. Because `Money.compactDisplay` starts abbreviating at 1,000 in English locales and 10,000 in Chinese locales, common values can lose precision in places where the user expects an exact balance. Some dense rows benefit from compact values to preserve scannability, but summary cards and detail summaries are decision surfaces and need accurate numbers.

`RecordEditorView` already distinguishes new expense creation from existing-record inspection with `hasEditIntent`. The current implementation hides top save/cancel actions for idle existing records, but the same state also hides the delete section. Cancel from edit mode resets local draft state and hides the toolbar actions without dismissing the sheet, which leaves users in the same panel after asking to cancel.

The home screen should not expose a search field in the main Groups list. Group detail record search and member lookup remain separate workflows.

## Goals / Non-Goals

**Goals:**
- Use exact signed money display for balance summary/detail surfaces, including home total balance, group "My balance", and member balance detail headers.
- Preserve compact signed money display for dense entry rows such as group rows, balance preview rows, expense rows, and settlement rows, but only at 100,000+.
- Keep zero balances visually consistent with the entry point that led to a balance detail.
- Keep delete visible for existing-record editors even before edit intent.
- Make existing-record cancel discard the draft and close the sheet without sending an update.
- Remove the home Groups search affordance while preserving group detail record search behavior.

**Non-Goals:**
- Changing money storage, parsing, arithmetic, currency, or server payload shapes.
- Removing compact display from dense rows entirely.
- Redesigning record editor layout or moving delete into the toolbar.
- Removing group detail record search or member lookup search.

## Decisions

1. Introduce explicit money display contexts.

   Keep `Money.display` as the exact major-unit formatter and keep `Money.compactDisplay` for dense contexts, but make callers choose the desired behavior rather than relying on a single signed helper everywhere. The likely implementation is a small helper such as `signedMoney(_:style:)` or separate exact/compact helpers. Summary/detail callers choose exact display with SwiftUI scaling (`lineLimit`, `minimumScaleFactor`, and monospaced digits); dense row callers choose compact display.

   Alternative considered: globally raise the threshold and leave all callers on `signedMoney`. This fixes the 1k/10k issue but does not satisfy the stronger requirement that summary/detail surfaces should always communicate exact values.

2. Raise the compact threshold to 100,000 major currency units.

   Compact display should return exact output for 1,000 and 10,000-range values. Only amounts whose absolute major-unit value is at least 100,000 should use localized compact suffixes. This keeps group and record rows compact for truly large values while avoiding premature information loss.

   Alternative considered: use different thresholds per surface. That would be more flexible, but it makes the rule harder to test and explain. A single compact threshold plus explicit exact contexts matches the product intent.

3. Treat zero color as a surface-level choice.

   `moneyColor` currently maps zero to muted ink. Dense rows may keep that behavior where it is already part of the row presentation, but member balance detail headers should use the same primary amount treatment as the surrounding entry surfaces when the value is zero. Prefer a local color helper or display-style option over changing every zero amount globally.

   Alternative considered: change `moneyColor` globally so zero always uses primary ink. That may unintentionally alter dense row hierarchy outside this bug.

4. Separate destructive availability from edit intent.

   Existing-record delete is not part of the top save/cancel action space. The delete section should render for any existing record, including the idle inspection state. Tapping delete may show confirmation immediately; it does not need to reveal save/cancel first.

   Alternative considered: requiring edit intent before delete. That caused the regression and makes a destructive but explicit action harder to discover.

5. Make cancel close the existing-record editor.

   For existing records, cancel in edit mode should reset draft state, avoid persistence, dismiss the sheet, and run the existing completion callback. Idle existing records still have no top cancel action. New expense cancel remains a normal dismissal.

   Alternative considered: cancel resets and stays open. That is useful for an "undo" affordance, but the existing toolbar action is presented as closing/canceling the panel.

## Risks / Trade-offs

- [Risk] Exact summary amounts can overflow in very narrow widths or with very large balances -> Mitigation: keep one-line text with minimum scale factor and avoid fixed trailing widths in summary cards.
- [Risk] Multiple money helpers can drift -> Mitigation: centralize the style choice in one shared helper and cover threshold behavior with focused verification.
- [Risk] Changing cancel to dismiss can surprise users who expected to continue viewing after discard -> Mitigation: idle existing records already support view-only inspection without top cancel/save actions; cancel appears only after explicit edit intent.
- [Risk] Removing the home search UI could accidentally affect group detail record search -> Mitigation: keep the edit scoped to `RootHomeView` and verify detail search call sites remain.
