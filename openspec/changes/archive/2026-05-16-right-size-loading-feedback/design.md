## Context

WalkCalc already has several good local feedback patterns: login disables the button and shows a `ProgressView`, join group keeps the sheet open and swaps the confirmation icon for a spinner while submitting, record search shows a small row-level spinner after debounce, and pagination uses inline footers. The weaker pattern is user-initiated mutations that still depend on store-wide `isLoading` or no local pending state. Record add/edit currently keeps the toolbar checkmark static while awaiting `addRecordWithFeedback` or `editRecordWithFeedback`, then closes only after the result returns.

The design needs to match Apple HIG rather than maximize visible indicators. Apple guidance relevant here:

- Progress indicators communicate that an app is not stalled while loading or performing lengthy work.
- Use determinate progress when duration is known and indeterminate progress when it is not.
- Keep indicators moving, transient, and in a consistent location.
- Show something when loading takes more than a moment or two, but avoid disrupting the experience when content can appear instantly or update in the background.
- Feedback should confirm outcomes or status in ways that are useful and unobtrusive.

Existing local product guidance in `docs/common-ux.md` already says background sync should not show success toasts, cached content should stay visible on refresh failure, and user-initiated failures should stay tied to the initiating action.

## Goals / Non-Goals

**Goals:**
- Make pending user-initiated network mutations visibly connected to the tapped control.
- Keep sheets, panels, and editors open until submitted work succeeds.
- Preserve drafts and context on failure so people can retry or cancel.
- Stop local progress indicators promptly on failure or cancellation.
- Suppress feedback for instant local actions, successful background refresh, and content changes that are already obvious.
- Reduce reliance on global blocking overlays for ordinary sheet/detail mutations.
- Keep the implementation native SwiftUI and consistent with existing toolbar/checkmark patterns.

**Non-Goals:**
- Add global success toasts, celebratory messages, or a new notification system.
- Show loading for every async task.
- Redesign the record editor, group settings, search canvas, or balances workspace.
- Add retry queues, offline drafts, or backend API changes.
- Replace native pull-to-refresh, search, or pagination loading affordances.
- Add determinate progress where the client cannot accurately estimate completion.

## Decisions

1. Use a feedback decision matrix, not blanket spinners.

   Classify each operation by user intent and UI consequence:

   - **Blocking user submission:** record save, create group, rename group, add members, archive/delete/restore, settlement actions. Show local in-control or surface-local indeterminate progress, disable duplicate submission, and keep the initiating surface open.
   - **Content loading with visible empty or partial content:** bootstrap, first group/detail load, pagination, search, member records. Use existing native or inline progress in the content area.
   - **Background refresh with usable content:** pull refresh completion, home refresh, secondary refresh, settlement suggestion refresh. Prefer no additional feedback beyond native refresh control or updated content.
   - **Instant local edits:** selecting members, choosing category, changing date, clearing search, adding temporary member names locally. Do not show progress.

   Rationale: This follows HIG's emphasis on progress indicators for ongoing work without adding redundant status for immediate interactions.

   Alternative considered: put every async operation behind a shared global overlay. That is simpler but hides which action is pending, blocks unrelated controls, and makes routine work feel heavier than it is.

2. Put pending state in the initiating view for submission buttons.

   Each sheet/editor that owns a confirmation action should own local state such as `isSubmitting` or `pendingAction`. The confirmation button renders `ProgressView().controlSize(.small)` in the same placement where the `checkmark` normally appears, keeps the same button style/tint, disables repeat taps, and updates the accessibility label to the action in progress when useful.

   Rationale: The spinner appears exactly where the user tapped, preserving spatial causality and avoiding vague app-wide busy states.

   Alternative considered: drive all button spinners from `WalkcalcStore.isLoading`. That cannot distinguish concurrent operations or tell which sheet action is pending, and it risks making unrelated controls look blocked.

3. Treat successful submission as the only automatic dismissal trigger.

   For record add/edit and similar sheets, the submit task sets pending state before awaiting the store result. On success, dismiss and call `onDone`. On failure, clear pending state, keep the surface open, keep the draft values intact, and show only actionable local copy from validation or business-rule responses.

   Rationale: Closing before the server confirms success makes people lose context, while leaving a failed form open lets them correct and retry.

   Alternative considered: optimistically dismiss and revert on failure. That creates harder-to-follow navigation and can make failed saves look like successful saves.

4. Standardize a small reusable confirmation-loading label only if duplication appears.

   Start by implementing local state in the affected views. If multiple toolbar confirmation buttons repeat the same `if isSubmitting { ProgressView() } else { Image(systemName: "checkmark") }` structure, introduce a small shared `AsyncConfirmationIcon` or view modifier under `Shared/UI`.

   Rationale: The pattern is simple enough to avoid premature abstraction, but a tiny shared view can protect consistency if the same code spreads.

   Alternative considered: build a full async button component. Current buttons differ in labels, placement, validation, error handling, and dismissal behavior, so a broad component would likely obscure local flow details.

5. Keep background and search feedback content-scoped.

   Existing search and pagination feedback should remain inline. The search canvas may show "Searching records..." while a non-empty query is debounced or loading. Pagination may show "Loading more..." at the list footer. Pull-to-refresh should rely on the native refresh control and content updates.

   Rationale: These operations load content but do not block the current task. HIG favors keeping people able to continue when content can load in the background.

   Alternative considered: show a global network busy indicator for all fetches. That would fight the non-interrupting network feedback work and make cached content feel unavailable.

## Risks / Trade-offs

- Local pending state gets out of sync with store result -> Use `defer` inside submit tasks where possible and ensure every failure path clears pending before returning.
- Duplicate submissions still possible through keyboard submit or alerts -> Gate submit functions with `guard !isSubmitting` and disable related controls while pending.
- Spinner-only buttons may be ambiguous to VoiceOver -> Keep or update accessibility labels such as `Save`, `Saving`, `Join`, or `Joining`.
- Over-suppressing feedback for slow operations -> Apply the matrix during audit; if an operation blocks user intent for more than a moment, add local progress.
- Too much shared abstraction -> Start with record editor and obvious toolbar confirmations, then extract only repeated rendering primitives.
- Generic failures with no message can look like nothing happened -> Keep the surface open, stop the spinner, and show useful fallback only when the action truly needs it; otherwise avoid generic "Network issues" copy already covered by quiet feedback rules.

## Migration Plan

1. Add a short loading-feedback checklist to the implementation task and scan confirmation toolbar buttons, alert destructive actions, and action sheets for async work.
2. Update `RecordEditorView` first: add `isSubmitting`, replace the save checkmark with local `ProgressView` while pending, disable cancel/save/delete during submission as appropriate, and keep the editor open on failure.
3. Review existing good patterns (`JoinGroupSheet`, login, search, pagination) and leave them unchanged unless they violate the new spec.
4. Add local pending state to create group, group settings rename/archive/delete, add members, archived restore/delete, record delete confirmation, and settlement actions where the current flow can otherwise look stalled.
5. Remove or narrow global `store.isLoading` overlay usage for ordinary local mutations once every initiating surface has local feedback.
6. Build and manually verify success/failure for representative record, group, search, pagination, and refresh flows.

## Open Questions

- Should destructive alert buttons show pending progress inside the alert action, or should the confirmation dismiss and show pending state on the underlying row/sheet? SwiftUI alert buttons offer limited custom content, so implementation may need the least awkward native option.
- Should generic transport failure for a submitted record show a local retry message, or stay silent with only the stopped spinner when the backend gives no actionable copy?
