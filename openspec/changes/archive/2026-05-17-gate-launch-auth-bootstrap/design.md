## Context

`ContentView` currently renders `LoginScreen(isSigningIn: false, onLogin: {})` while `WalkcalcStore.isBootstrapping` is true. Because `WalkcalcStore` loads any saved token from `UserDefaults` before bootstrap completes, startup has three different states but only two routed destinations: authenticated home or login. The missing state is "authentication is still being resolved."

The current bootstrap sequence warms network access, requests notification permission, then calls `store.bootstrap()`. Inside `bootstrap()`, the store validates the saved token with `/auth/info` and, if successful, loads home data. While that work is pending, the UI is already showing a full login screen with a disabled/no-op login action. For valid saved sessions, that produces the visible sequence reported by the user: system splash, login-looking screen, loading/home.

## Goals / Non-Goals

**Goals:**
- Represent startup routing as an explicit launch/auth gate instead of treating bootstrapping as login.
- Keep the post-launch SwiftUI surface visually aligned with the launch/splash brand state while saved-session validation is unresolved.
- Show login only after the app knows there is no saved token or the saved token is unusable.
- Show authenticated content only after saved-session validation has succeeded and startup home bootstrap has completed or settled.
- Preserve fixture mode and explicit SSO login behavior.

**Non-Goals:**
- Redesign the login screen or SSO sheet.
- Change backend authentication APIs, token storage keys, or refresh semantics.
- Add a new dependency or a long artificial startup delay.
- Block users on notification permission before routing unless current app behavior already requires it.
- Replace content-scoped loading inside authenticated screens after routing.

## Decisions

1. Model startup as a route state, not a derived pair of booleans.

   Add a small store-owned startup route/state such as `launchRoute` or `startupPhase` with values equivalent to resolving, loginRequired, and authenticated. `ContentView` should switch on that state rather than inferring route from `isBootstrapping` and `isLoggedIn`.

   Rationale: `isBootstrapping` describes work in progress, while `isLoggedIn` describes current data. Combining them currently makes the app render login during an unknown state. A route state makes unknown, unauthenticated, and authenticated mutually exclusive.

   Alternative considered: keep `isBootstrapping` and render a different view in the existing first branch. That fixes the visible flash but keeps route decisions spread across boolean combinations, which makes token rejection and fixture behavior easier to regress.

2. Introduce a static launch gate view instead of reusing `LoginScreen`.

   Add a lightweight SwiftUI view for the resolving phase. It should match the existing brand/splash visual language but omit login copy, the login button, and any explicit progress/loading indicator.

   Rationale: Reusing `LoginScreen` communicates that the user must log in, and the no-op login button is a broken interaction while bootstrap is pending.

   Alternative considered: disable and hide only the login button inside `LoginScreen`. That still couples launch and login presentation and makes future login copy/layout changes affect startup.

3. Treat saved-session validation as the routing boundary.

   On app start:
   - If fixture mode is active, route directly according to fixture data and finish resolving.
   - If no saved token exists, route to login without performing authenticated home bootstrap.
   - If a saved token exists, keep the launch gate visible while validating user info.
   - If validation rejects the token, clear auth state and route to login.
   - If validation succeeds, keep the launch gate visible while required startup home data work runs, then route to authenticated content.

   Rationale: The login screen should mean "the app knows you need to log in," not "the app is still checking."

   Alternative considered: route to home immediately after user validation and let home show its own loading. That is acceptable for secondary content, but it can still create a splash-to-empty-home jump before the initial data has settled.

4. Keep startup tasks ordered around user-visible routing.

   `prepareNetworkAccessForStartup()` can remain before auth bootstrap because it helps the first auth request. Notification permission should not be allowed to force a login-looking interstitial; either keep it outside route decisions or run it after the route is known if it causes visible delay.

   Rationale: The user-visible startup gate should be owned by auth/session readiness, not by unrelated permissions.

   Alternative considered: include all startup tasks in one `isBootstrapping` flag. That is what currently makes unrelated work prolong the login-like intermediate screen.

## Risks / Trade-offs

- Startup can feel longer for valid sessions because login is no longer shown as an intermediate surface -> Mitigate by making the launch gate calm and branded without introducing a separate loading state.
- Network failure while validating a saved token may strand users on launch if not handled -> Mitigate by defining a terminal policy: token rejection clears to login; transient validation failure either routes to login with token preserved only if retry is not available, or shows a retryable launch-state error.
- Existing debug fixture behavior could be broken by new route state -> Mitigate with an explicit fixture branch and manual verification.
- Initial home refresh failure after valid auth could block routing too long -> Mitigate by treating required auth validation as mandatory and home data refresh as "complete or settled"; failures should allow authenticated routing with empty/cached state per existing quiet network behavior.
- A new splash view can drift from the native launch screen and login brand -> Mitigate by reusing the existing brand mark/layout primitives where practical.

## Migration Plan

1. Add the explicit startup route/state to `WalkcalcStore` and initialize it to resolving.
2. Update `bootstrap()` so every path reaches a terminal route: loginRequired or authenticated.
3. Add a dedicated launch gate view in `HomeViews.swift` and render it from `ContentView` while startup is resolving.
4. Remove the no-op bootstrapping use of `LoginScreen`.
5. Verify cold launch paths for no token, valid token, invalid token, validation failure, fixture mode, and manual SSO sign-in.

## Open Questions

- Should transient `/auth/info` network failure preserve the saved token and show a retryable launch gate, or clear to login immediately? The implementation should choose the least surprising behavior based on current `fetchUser` failure handling and existing quiet network feedback rules.
