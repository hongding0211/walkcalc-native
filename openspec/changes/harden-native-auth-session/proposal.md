## Why

WalkCalc native can persist an access token but does not reliably preserve the backend refresh credential used by `/auth/refreshToken`, so an expired access token can look like a random lost login. When refresh fails, many authenticated requests classify the failure as ordinary silent network feedback, leaving the app on the current screen instead of routing the user back to login.

## What Changes

- Persist and reuse the complete native session contract needed for access-token refresh, not only the current access token.
- Keep the backend refresh semantics unchanged: refresh uses the httpOnly refresh-token cookie, rotates the refresh session, and returns a new access token.
- Bridge or otherwise preserve login WebView refresh credentials so native API calls can refresh after the login sheet is dismissed.
- Update the native API/store error path so unrecoverable 401/403 or refresh failure becomes a single session-expired outcome.
- Route immediately to the login screen after an unrecoverable auth failure, clearing local auth and ledger state.
- Keep recoverable background refresh failures quiet, but do not treat authentication loss as a recoverable background failure.
- Add focused verification for expired access tokens, missing/expired refresh credentials, rotated refresh credentials, and normal backend auth rejection.

## Capabilities

### New Capabilities
- `native-auth-session-recovery`: Defines how the native app stores, refreshes, rotates, and clears authenticated session state after SSO login.

### Modified Capabilities
- `quiet-network-error-feedback`: Authentication loss is no longer eligible for silent background suppression; the app must route to sign-in when refresh cannot recover the session.

## Impact

- Affected native code: `walkcalc-native/Features/Auth/SSOLoginView.swift`, `walkcalc-native/Core/Networking/APIClient.swift`, `walkcalc-native/App/WalkcalcStore.swift`, and any shared auth/session helper introduced for cookie or credential persistence.
- Affected backend code for verification only: `/auth/refreshToken`, refresh-session rotation, auth guard 401 handling, and auth cookie names/options in `hong97-ltd-next`.
- No intended backend API contract change; backend work should be limited to tests or diagnostics unless implementation discovers a concrete server defect.
- Security impact: refresh credentials must remain unavailable to app UI, logs, and JavaScript-visible storage; native persistence must use platform-protected storage or the system cookie store rather than plain `UserDefaults`.
