## Context

The native app currently stores only `walkcalc.token` in `UserDefaults` and treats that value as the saved session. `APIClient.request` retries any 401/403 by calling `POST /auth/refreshToken`, then persists the returned access token through `APIEnvelope.refreshedToken`.

The backend refresh contract is cookie-based. Login and GitHub OAuth issue an access token plus a refresh session, set httpOnly `accessToken` and `refreshToken` cookies, and `/auth/refreshToken` reads only the refresh-token cookie before rotating the stored refresh session and setting a new cookie. The refresh token is intentionally not returned in the response body.

The native SSO login currently loads the web flow in a non-persistent `WKWebsiteDataStore`, clears shared cookies for the auth host, extracts the access token from the callback, and only persists that access token. It calls `getAllCookies` but does not copy refresh cookies into the shared `HTTPCookieStorage`, persistent `WKWebsiteDataStore`, or another protected native store. After the login sheet is dismissed, native `URLSession.shared` often has no refresh-token cookie to send, so an expired access token leads to a failed refresh.

When refresh fails, `APIClient` throws `APIClientError(kind: .authRefresh)`. Most store calls catch that error and pass it to `recordFailure(... disposition: .silent ...)`, which only logs diagnostics. This is why a background or subsequent user request can fail with no visible transition even though the app is no longer authenticated.

## Goals / Non-Goals

**Goals:**
- Preserve the backend refresh credential across the native login boundary without exposing it to app UI, logs, or JavaScript-visible storage.
- Keep access-token refresh automatic and serialized so concurrent 401/403 responses cause at most one refresh operation.
- Treat unrecoverable auth refresh failure as a session-expired event that clears auth state and routes to login.
- Keep existing quiet handling for ordinary transport, pagination, and recoverable background refresh failures.
- Verify that the observed behavior is primarily a native session handling problem while leaving room for backend tests if refresh rotation or cookie attributes prove defective.

**Non-Goals:**
- Replace the backend cookie-based refresh contract with refresh tokens in JSON response bodies.
- Redesign SSO login, profile WebView navigation, or backend OAuth endpoints.
- Add noisy alerts for routine background refresh failures.
- Change WalkCalc ledger authorization rules or permanent API token behavior.

## Decisions

1. **Use a native session bridge for refresh credentials.**
   Capture the auth cookies from the SSO WebView at successful login and make them available to native refresh calls. The preferred implementation is to copy only auth-host cookies needed by the backend into shared `HTTPCookieStorage` with their server-provided attributes preserved, so `URLSession.shared` can send them to `/auth/refreshToken`.

   Rationale: The backend already protects the refresh token with httpOnly cookies and refresh-session rotation. Reusing that contract avoids introducing a second native-only credential format.

   Alternative considered: ask the backend to return refresh tokens to the native client. That would widen the server contract and expose a long-lived credential through JSON; it is unnecessary if native cookie persistence is fixed.

2. **Keep access token storage separate from refresh credential storage.**
   Continue storing the current access token as the bearer credential for protected API requests, but replace it whenever a refresh response returns `accessToken`. Do not persist refresh tokens in `UserDefaults`.

   Rationale: Access tokens are short-lived and already part of the current native contract. Refresh credentials have higher sensitivity and should stay in protected cookie/keychain-backed infrastructure.

   Alternative considered: move both access and refresh credentials into Keychain immediately. This can be valid later, but a cookie bridge is the smallest change that matches the existing backend behavior and web SSO flow.

3. **Classify auth refresh failure before operation-level feedback disposition.**
   Add a store-owned path such as `handleAuthFailure` or an auth-specific result from API calls. Any `APIClientError.kind == .authRefresh`, unrecovered 401/403 response, or bootstrap user validation rejection should clear `token`, `user`, ledger caches, and auth cookies, then set `startupRoute = .loginRequired`.

   Rationale: Whether the failing request was background refresh, pagination, search, or user action is secondary once the session cannot be recovered. The app cannot keep pretending to be authenticated.

   Alternative considered: show a session-expired alert while staying on the current screen. That adds an extra dead-end state; routing to login is simpler and matches the user's expectation.

4. **Refresh exactly once per failed request before logging out.**
   Preserve the existing `AuthRefreshCoordinator` serialization and single retry. Only transition to login after the refresh endpoint fails, returns no token, or the retried request still rejects authentication.

   Rationale: Expired access tokens are expected; forced logout should happen only when refresh cannot recover the session.

   Alternative considered: logout immediately on any 401/403. That would break normal short-lived access tokens and waste the backend refresh session contract.

5. **Add backend verification without assuming a backend defect.**
   Verify that `/auth/refreshToken` accepts a valid refresh cookie, rotates the session, sets a replacement refresh cookie, rejects missing/expired/reused cookies with 401, and does not allow refresh cookies to authorize protected APIs.

   Rationale: Current backend code matches the intended contract, but tests make the native diagnosis falsifiable and protect against regressions in cookie attributes or refresh rotation.

## Risks / Trade-offs

- Auth cookies copied with the wrong domain/path/security attributes could still fail to reach `/auth/refreshToken` -> Preserve server cookie attributes where possible and add a local verification path for both debug loopback and production host configuration.
- Non-persistent WebView login may intentionally isolate cookies, so bridging only selected auth cookies must avoid copying unrelated web session state -> Filter by auth host and known auth cookie names.
- Concurrent expired-token requests could race with logout or token replacement -> Keep `AuthRefreshCoordinator` and make logout/session-expired handling idempotent on the main actor.
- Refresh success followed by a retried 401/403 may indicate revoked user access rather than missing cookies -> Treat it as unrecoverable auth and route to login after diagnostics.
- Clearing auth state during an edit could discard unsaved local input if the view is replaced -> Prefer routing behavior required by auth loss, and rely on existing local action pending state only until the transition happens.

## Migration Plan

1. Add a native auth session helper that knows the backend auth cookie names and can import, persist, clear, and verify auth cookies for `APIClient.baseURL`.
2. Wire `SSOLoginView.completeLogin` to import cookies before calling `signIn`.
3. Update `APIClient.refreshAccessToken` and request retry handling to preserve structured auth-refresh failure metadata and detect a retried 401/403.
4. Add a single `WalkcalcStore` auth-failure path used by bootstrap, background refreshes, pagination, secondary loads, and user actions.
5. Clear persisted access token and auth cookies on explicit logout and unrecoverable auth failure.
6. Add tests or debug verification for successful refresh, missing refresh cookie, expired/reused refresh cookie, retried 401/403, and normal non-auth network failures.

Rollback is local to the native app unless backend verification exposes a server issue. If cookie bridging causes unexpected behavior, disable automatic refresh and force login on access-token expiry rather than leaving silent failures.
