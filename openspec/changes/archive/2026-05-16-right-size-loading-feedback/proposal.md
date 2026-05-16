## Why

Several user-initiated operations currently provide little or overly broad in-flight feedback, so people can mistake a pending network mutation for a frozen app. Record save is the clearest example: the confirmation checkmark stays visually unchanged while the request is running, and the editor can only close or remain open after the async result returns.

This should be tightened without making the app noisy. Per Apple HIG, progress indicators are transient and useful when work takes more than a moment, while instant or background work should stay quiet and let the content update speak for itself.

## What Changes

- Add a right-sized loading feedback policy for user-initiated operations, background refreshes, pagination, and instant local actions.
- Replace static confirmation icons with local in-control progress only while user-initiated submissions are awaiting an async result, starting with record add/edit save.
- Keep the initiating sheet or panel open while a submitted operation is pending.
- Close the initiating surface only after the operation succeeds.
- Keep the initiating surface open on failure, preserve the user's draft/context, stop the progress indicator, and show concise local feedback only when the message is useful.
- Continue suppressing routine success feedback for fast actions, background refresh, search debounce, and content updates where the result is already visible.
- Avoid adding redundant global spinners, modal alerts, success toasts, or explanatory loading copy for operations that complete immediately or do not block the user's current intent.

## Capabilities

### New Capabilities
- `right-sized-operation-progress`: Defines when WalkCalc shows, suppresses, or localizes loading/progress feedback for async operations.

### Modified Capabilities
- `intentional-record-editing`: Existing record and new-expense saves must show local submission progress, defer dismissal until success, and preserve the editor on failure.
- `quiet-network-error-feedback`: User-initiated failures must stop local progress and leave the initiating surface retryable, without falling back to global loading or generic modal feedback.

## Impact

- Affected code: `walkcalc-native/Features/Groups/GroupPanels.swift`, `walkcalc-native/Features/Groups/GroupViews.swift`, `walkcalc-native/Features/Home/HomeViews.swift`, `walkcalc-native/App/WalkcalcStore.swift`, and any shared UI helpers added under `walkcalc-native/Shared/UI`.
- UX docs/specs: align with `docs/common-ux.md`, `docs/groups-detail.md`, and Apple HIG guidance for loading, progress indicators, and feedback.
- APIs: no backend API changes expected.
- Dependencies: no new external dependencies expected; use SwiftUI `ProgressView`, existing `StoreActionResult`, local state, and existing feedback/logging infrastructure.
- Verification: build the app, scan for async confirmation buttons without pending state, and manually verify record save success/failure, record delete, create/join group, group settings actions, search, pagination, and pull-to-refresh.
