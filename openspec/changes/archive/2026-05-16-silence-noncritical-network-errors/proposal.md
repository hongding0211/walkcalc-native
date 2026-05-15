## Why

Routine usage can currently surface generic "Network issues" modal alerts even when the failed request is background refresh, pagination, push registration, or otherwise recoverable. For a user-facing daily app, non-critical network failures should not interrupt the current flow, and the client should be easier to inspect when a network error does appear.

## What Changes

- Audit all network failure paths that currently write to global user-facing error state.
- Replace the global modal "Network issues" alert behavior with a severity-aware feedback model.
- Keep background refresh, pagination, cache refresh, push registration, and other recoverable network failures silent when existing content remains usable.
- Surface user-initiated failures only in the local context of the action, using inline or lightweight non-blocking feedback where possible.
- Reserve modal alerts for urgent failures that block the current flow, risk data loss, require re-authentication, or require an explicit user decision.
- Add lightweight diagnostics so unexpected network failures can be investigated without exposing generic backend or transport text to end users.

## Capabilities

### New Capabilities
- `quiet-network-error-feedback`: Defines how the app classifies, records, and surfaces network or server failures without interrupting users unnecessarily.

### Modified Capabilities
- None.

## Impact

- Affected code: `walkcalc-native/App/WalkcalcStore.swift`, `walkcalc-native/Core/Networking/APIClient.swift`, global feedback in `walkcalc-native/Features/Home/HomeViews.swift`, and action-specific views that currently depend on `store.errorMessage`.
- APIs: no backend API changes expected.
- Dependencies: no new external dependencies expected; use existing Swift, `Logger`/OSLog, and local UI components.
- Verification: code scan for `errorMessage` writers, simulator/manual checks for background refresh, pagination, join/create/edit/archive/delete flows, and build/test coverage for error classification.
