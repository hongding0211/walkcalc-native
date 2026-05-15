## 1. Failure Audit And Classification

- [x] 1.1 Re-scan production code for every `errorMessage` writer and every `catch` around `APIClient` calls.
- [x] 1.2 Classify each network operation as background refresh, pagination, search/secondary load, user-initiated action, bootstrap/auth, or data-loss-sensitive mutation.
- [x] 1.3 Document which current paths can produce generic "Network issues" alerts and whether each should be silent, local feedback, non-blocking notice, or urgent alert.

## 2. Network Failure Model

- [x] 2.1 Add a typed failure or feedback model that can represent transport, server envelope, HTTP status, auth refresh, validation/business-rule, and cancellation outcomes.
- [x] 2.2 Update `APIClient` to preserve structured failure metadata needed for classification without exposing tokens or request bodies.
- [x] 2.3 Add lightweight `Logger` diagnostics for suppressed failures with operation name, failure category, and user-feedback decision.

## 3. Global Feedback Removal

- [x] 3.1 Remove or narrow the `ContentView` global generic `store.errorMessage` modal alert so routine network failures cannot interrupt the app.
- [x] 3.2 Replace background refresh, home refresh with cached data, pagination, record search, member-record loading, group-balance loading, and settlement-suggestion failure paths with silent or non-blocking handling.
- [x] 3.3 Ensure all converted loaders clear their loading state and preserve existing visible content after failure.

## 4. Local Action Feedback

- [x] 4.1 Keep join-group failure feedback local to the join sheet and confirm it never triggers a global network alert.
- [x] 4.2 Convert create, rename, archive, delete, member, record, and settlement mutations that need user feedback to return local action results instead of writing global generic errors.
- [x] 4.3 Preserve server validation, authorization, duplicate, settlement-limit, and business-rule messages as local action feedback when safe and useful.
- [x] 4.4 Keep modal alerts only for urgent auth, data-loss, or explicit decision-required cases.

## 5. Verification

- [x] 5.1 Build the native app and fix any compile issues from the feedback model migration.
- [x] 5.2 Manually verify offline or failed-server behavior for home refresh, pagination, record search, member record loading, and settlement suggestions: content remains usable and no generic modal alert appears.
- [x] 5.3 Manually verify failed user actions from sheets/detail views keep the user in context with retry or cancel available.
- [x] 5.4 Re-run a code scan confirming no remaining `errorMessage = L("Network issues")` path can fire for non-urgent network failures.
