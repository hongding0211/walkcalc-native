## Context

The current app has one global user-facing error channel: `WalkcalcStore.errorMessage`. `ContentView` observes it and presents a modal `Notice` alert. Many unrelated paths write to that property, including bootstrap user loading, home refresh, pagination, group/detail refresh, record search, member record loading, settlement suggestion refresh, and the shared `withLoading` helper used by user actions.

That makes transport failures look more severe than they are. A transient failed refresh can interrupt browsing with a generic "Network issues" alert even when cached content is still usable. Some paths are already quieter, such as push device registration using `try?`, and join group already returns a local `JoinGroupResult` so the sheet can show inline feedback.

Existing UX guidance in `docs/common-ux.md` says background sync failure must not use modal alerts, cached content should stay visible, and only failures that matter to the current screen should surface subtle non-blocking feedback.

Likely current causes of the observed network popups:

- `URLSession.shared.data(for:)` throws for transport failures, DNS failures, TLS issues, connection resets, timeouts, or cancellation, and most callers convert that into `errorMessage = L("Network issues")`.
- Non-success backend envelopes in refresh-like calls often write `response.message ?? L("Network issues")` to the same global alert.
- `withLoading` catches any thrown error from create/archive/delete/update operations and promotes it to a global alert with no context.
- Refresh token retry can throw from `APIClient.execute`; callers receive only a thrown error and cannot distinguish auth expiry from transient network failure.
- Background/secondary loads such as pagination, record search, member records, group balances, and settlement suggestions use the same alert channel as blocking actions.

## Goals / Non-Goals

**Goals:**
- Remove routine global "Network issues" modal alerts from recoverable background and secondary network failures.
- Classify network/server failures by user impact before surfacing them.
- Keep cached content visible when refresh, pagination, search, or secondary detail loads fail.
- Give user-initiated actions local feedback when the action cannot complete.
- Preserve urgent modal prompts only for failures that block the current flow, risk data loss, require re-authentication, or require an explicit user decision.
- Add developer diagnostics for unexpected network/server failures without exposing raw transport details to users.

**Non-Goals:**
- Change backend API contracts or response envelope shapes.
- Add an offline mode, persistent retry queue, or conflict-resolution system.
- Redesign all failure UI surfaces.
- Hide validation, authorization, settlement-limit, or destructive-action confirmations that are part of the task the user initiated.
- Change push notification permission or APNs registration behavior except to keep registration failure silent.

## Decisions

1. Replace global string errors with typed app feedback.

   Introduce a small store-level error classification model, such as `AppFeedback` or `NetworkFailurePolicy`, with severity values for `silent`, `inline`, `nonBlockingNotice`, and `urgentAlert`. Network call sites pass intent metadata: background refresh, pagination, search, user action, bootstrap/auth, or data-loss-sensitive mutation.

   Rationale: the current `String?` has no context, so the view can only show a modal. Typed feedback makes "do nothing" an explicit and testable outcome.

   Alternative considered: remove all assignments to `errorMessage`. That would stop popups quickly but would also hide failures for blocking user actions.

2. Keep global modal alerts out of routine network handling.

   Remove the `ContentView` global alert dependency for generic network failures. If a global alert channel remains, restrict it to urgent cases with explicit titles and actions, not generic transport text.

   Rationale: background refresh and pagination can fail while the current screen remains useful. Interrupting the user is disproportionate and inconsistent with the documented UX guidance.

   Alternative considered: keep the global alert but rate-limit it. Rate limiting reduces frequency but still lets non-critical failures interrupt the user.

3. Return local action results for user-initiated mutations.

   Expand the existing `JoinGroupResult` pattern into a reusable action-result shape for create, rename, archive, delete, record creation/editing, record deletion, and settlement actions where needed. Views that initiate an action decide whether to keep a sheet open, show inline text, show a subtle notice, or simply leave the view unchanged.

   Rationale: a failed join belongs in the join sheet; a failed archive belongs next to the archive interaction. Local feedback is clearer and avoids global modal interruption.

   Alternative considered: store a single non-blocking toast on `WalkcalcStore`. That is useful for some cases but cannot express field-level or sheet-local failures well.

4. Log diagnostics separately from user feedback.

   Add lightweight logging around classified failures using `Logger`, including operation name, failure category, HTTP status when available, and whether feedback was suppressed. Avoid logging tokens, group names, notes, or request bodies.

   Rationale: the user asked to investigate possible causes. Once popups are silent, developers still need evidence for whether failures are transport, auth, server envelope, cancellation, or refresh-token related.

   Alternative considered: keep raw errors in visible copy. That helps debugging but is inappropriate for a user-facing app.

5. Normalize API error metadata at the networking boundary.

   Keep `APIEnvelope` for successful decoding, but add enough structured error information for callers to classify failures. Transport errors, HTTP status failures, non-success envelopes, and refresh-token failures should be distinguishable without each caller parsing `Error.localizedDescription`.

   Rationale: most current catch blocks collapse distinct failure modes to "Network issues", which makes investigation and correct UX policy difficult.

   Alternative considered: classify every catch site manually. That duplicates logic and increases the chance of inconsistent behavior.

## Risks / Trade-offs

- Over-suppressing a real blocking failure -> Mitigation: make action failures return local results and keep urgent alert support for auth/data-loss/decision-required cases.
- Too many call-site changes at once -> Mitigation: migrate by operation category, starting with the global alert and background/secondary refresh paths, then mutation flows.
- Developers lose visibility after user-facing alerts are removed -> Mitigation: log every suppressed failure with operation and category.
- Backend validation messages are accidentally hidden -> Mitigation: classify server validation and business-rule failures from user actions as local feedback, not silent network failures.
- Existing UI tests expect modal alerts -> Mitigation: update tests to assert stable cached content, inline action errors, or absence of global "Network issues" alerts depending on the operation.

## Migration Plan

1. Add the typed feedback/error policy and logging helpers in the app/store layer.
2. Update `APIClient` to preserve structured failure categories and HTTP status where available.
3. Remove or narrow `ContentView`'s generic `store.errorMessage` modal alert.
4. Convert background and secondary loaders to suppress recoverable failures while preserving cached data.
5. Convert user-initiated mutations to return local action results where the initiating view needs feedback.
6. Re-scan for all `errorMessage =` writers and remove or justify each remaining modal path.
7. Build and manually verify common online, offline, failed-server, and failed-action flows.

## Open Questions

- Should non-blocking notices be implemented in this change, or should recoverable failures stay fully silent until a concrete screen needs subtle feedback?
- Should auth-expired failures immediately log out, show a sign-in prompt, or silently retry until refresh fails with a confirmed unauthorized response?
