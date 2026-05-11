## 1. Record Editor Intent

- [x] 1.1 Add edit-intent state to `RecordEditorView`, initialized as active for new expenses and idle for existing records.
- [x] 1.2 Change record editor focus setup so existing records do not auto-focus any field, while new expenses can still focus the amount field.
- [x] 1.3 Show cancellation and confirmation toolbar actions only when the editor is in new-expense mode or existing-record edit mode.
- [x] 1.4 Enter existing-record edit mode when the user focuses amount/note or interacts with paid-by, split members, category, date, or delete controls.
- [x] 1.5 Ensure cancel from existing-record edit mode does not call the update API and save still validates before submitting edited values.

## 2. Balance Member Visibility

- [x] 2.1 Update the group detail balances preview to derive rows from the complete participant list, including the current user.
- [x] 2.2 Update the balances workspace root list to derive rows from the same complete participant list.
- [x] 2.3 Verify member balance detail filtering works for the current user and other members using the selected member's paid/for-whom relationship.
- [x] 2.4 Add or adjust localized self-facing copy only if the current-user balance detail title reads awkwardly in production UI.

## 3. Preview And Verification

- [x] 3.1 Align relevant design playground balance/editing previews with production behavior if they model these surfaces.
- [x] 3.2 Build the iOS app on the configured simulator and resolve any compiler issues.
- [x] 3.3 Manually verify existing-record open, edit-intent transition, save/cancel behavior, and balance lists including the current user.
- [x] 3.4 Remove the active group count suffix from the home "All groups" heading.
