## 1. Native Session Persistence

- [x] 1.1 Add a native auth session helper that can import backend auth cookies from `WKHTTPCookieStore` for the configured auth/API host.
- [x] 1.2 Persist only the backend auth cookies or refresh credential in platform-protected cookie/credential storage, preserving domain, path, expiration, secure, and httpOnly semantics where available.
- [x] 1.3 Ensure refresh credentials are never written to `UserDefaults`, app logs, request diagnostics, or JavaScript-visible storage.
- [x] 1.4 Clear preserved auth cookies or refresh credentials on explicit logout and session-expired logout.

## 2. SSO Login Bridge

- [x] 2.1 Update `SSOLoginView.completeLogin` to import auth cookies before calling the app sign-in callback.
- [x] 2.2 Handle local-password and GitHub OAuth login completion paths consistently, including callback-token and cookie-derived completion.
- [x] 2.3 Treat login completion without an importable refresh credential as a non-refreshable session and make the behavior diagnosable without exposing token values.

## 3. Refresh And Retry Semantics

- [x] 3.1 Keep 401/403 refresh serialized through `AuthRefreshCoordinator` so concurrent failures share one refresh call.
- [x] 3.2 Update refresh handling to persist a returned access token and any rotated auth cookie state after `/auth/refreshToken` succeeds.
- [x] 3.3 Detect missing refresh credential, rejected refresh, refresh response without access token, and retried 401/403 as unrecoverable auth outcomes.
- [x] 3.4 Preserve ordinary transport, cancellation, server-envelope, and business-rule failures as non-auth failures for existing feedback classification.

## 4. Store-Level Auth Expiry Routing

- [x] 4.1 Add an idempotent `WalkcalcStore` path for unrecoverable auth failure that clears token, user, ledger caches, pending sign-in state, and preserved auth credentials.
- [x] 4.2 Route to `.loginRequired` immediately after unrecoverable auth failure from bootstrap, home refresh, group refresh, pagination, search, secondary loads, push registration, and user actions.
- [x] 4.3 Ensure background refresh, pagination, and secondary-load auth failures are not logged only as `.silent` recoverable failures.
- [x] 4.4 Keep explicit login-required guards for calls that start with no token.

## 5. Backend Contract Verification

- [x] 5.1 Verify the backend refresh endpoint accepts a valid refresh cookie, returns `data.accessToken`, and sets rotated access/refresh cookies.
- [x] 5.2 Verify missing, expired, revoked, and reused refresh cookies are rejected by `/auth/refreshToken`.
- [x] 5.3 Verify refresh-token cookies alone cannot authorize protected WalkCalc APIs.
- [x] 5.4 Add backend tests or document an existing test path for refresh rotation if coverage is missing.

## 6. Native Verification

- [x] 6.1 Add focused native tests or debug verification for SSO login preserving refresh credentials.
- [x] 6.2 Verify expired access token plus valid refresh credential refreshes once, retries the original request, and persists the new access token.
- [x] 6.3 Verify missing or expired refresh credentials clear auth state and route to login after the next authenticated request.
- [x] 6.4 Verify ordinary offline/background failures remain quiet and do not force logout.
- [x] 6.5 Build the native app after implementation.
