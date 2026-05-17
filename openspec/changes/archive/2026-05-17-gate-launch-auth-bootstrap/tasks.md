## 1. Startup Route State

- [x] 1.1 Add an explicit startup route/state to `WalkcalcStore` for resolving, login required, and authenticated outcomes.
- [x] 1.2 Initialize startup routing so cold launch starts in the resolving state before saved-session validation finishes.
- [x] 1.3 Update `bootstrap()` so no-token, rejected-token, valid-token, validation-error, and fixture-mode paths all set a terminal startup route.
- [x] 1.4 Ensure saved-token validation failure does not leave `isBootstrapping` or the new route state stuck in resolving.

## 2. Launch Gate UI

- [x] 2.1 Add a dedicated launch/splash-style resolving view in `HomeViews.swift` that reuses the app brand visual language without login copy or a login button.
- [x] 2.2 Update `ContentView` to switch on the explicit startup route and render launch gate, login, or authenticated home from that route.
- [x] 2.3 Remove the bootstrapping branch that renders `LoginScreen(isSigningIn: false, onLogin: {})`.
- [x] 2.4 Keep explicit SSO sign-in progress unchanged inside `LoginView` and `LoginScreen`.

## 3. Bootstrap Sequencing

- [x] 3.1 Keep network warm-up compatible with the launch resolving state and first auth request.
- [x] 3.2 Ensure notification permission registration does not cause a login-looking interstitial during startup.
- [x] 3.3 After valid saved-session auth, keep the launch gate visible while required initial home bootstrap completes or settles.
- [x] 3.4 Allow authenticated routing after valid auth if home refresh fails without treating the user as logged out.

## 4. Verification

- [x] 4.1 Build the native app and fix Swift compile errors.
- [x] 4.2 Manually verify cold launch with no saved token routes from splash/launch gate to login without an inert login button phase.
- [ ] 4.3 Manually verify cold launch with a valid saved token routes from splash/launch gate to authenticated home without showing login.
- [ ] 4.4 Manually verify rejected saved token clears auth and routes to login.
- [ ] 4.5 Manually verify transient validation or initial home refresh failure reaches a user-visible terminal state and does not spin forever.
- [ ] 4.6 Manually verify fixture mode and explicit SSO sign-in still work as before.
