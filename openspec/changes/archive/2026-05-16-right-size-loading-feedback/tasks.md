## 1. Audit And Shared Pattern

- [x] 1.1 Scan production SwiftUI confirmation buttons, destructive alert actions, and async submit functions for operations that await store/network results without local pending feedback.
- [x] 1.2 Decide whether repeated toolbar confirmation rendering warrants a tiny shared `AsyncConfirmationIcon`/modifier under `walkcalc-native/Shared/UI`; keep view-local code if only a few call sites need it.
- [x] 1.3 Define a consistent local pending-state convention for affected views, including duplicate-submit guards, disabled states, and accessibility labels.

## 2. Record Editor Submission

- [x] 2.1 Add local `isSubmitting` state to `RecordEditorView` and guard `submit()` against duplicate calls.
- [x] 2.2 Replace the record editor save `checkmark` with a small indeterminate `ProgressView` while save/update is pending.
- [x] 2.3 Keep the new/edit record editor open while the save request is pending and dismiss only after `StoreActionResult.success`.
- [x] 2.4 On save/update failure, clear pending state, preserve amount/payer/split/category/date/note draft values, and show only useful local validation or business-rule feedback.
- [x] 2.5 Disable conflicting record-editor actions while submitting, including save repeat taps and destructive delete entry points.

## 3. Other User-Initiated Mutations

- [x] 3.1 Review create group, group settings rename/archive/delete, people setup add members, archived restore/delete, record delete, and settlement actions for missing local pending feedback.
- [x] 3.2 Add local pending indicators to async sheet or panel confirmation actions that remain visible during submission.
- [x] 3.3 Keep initiating sheets/panels open on failure, stop local progress, preserve input/selection context, and allow retry or cancel.
- [x] 3.4 Leave instant local-only actions without progress indicators, including local member selection, temporary-name staging, category selection, date changes, and search clearing.

## 4. Background And Content Loading

- [x] 4.1 Preserve existing content-scoped progress for bootstrap, initial loads, pagination, record search, and member-record loading.
- [x] 4.2 Verify background refresh and pull-to-refresh do not add redundant success messages or global progress overlays when cached content remains usable.
- [x] 4.3 Narrow or remove global `store.isLoading` overlay use for ordinary local mutations after initiating surfaces show their own pending state.

## 5. Verification

- [x] 5.1 Build the native app and fix any Swift compile errors.
- [x] 5.2 Manually verify record add success, record edit success, record add/edit failure, and duplicate save prevention.
- [x] 5.3 Manually verify create/join group, group settings mutation, record delete, and settlement mutation pending/failure behavior.
- [x] 5.4 Manually verify search, pagination, pull-to-refresh, and background refresh stay quiet or content-scoped according to the spec.
- [x] 5.5 Re-scan for async confirmation buttons still showing a static `checkmark` during pending network work and justify or fix each remaining case.
