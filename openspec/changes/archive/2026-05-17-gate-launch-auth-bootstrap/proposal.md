## Why

The app currently leaves the native launch/splash phase, briefly renders the login screen, then shows loading before entering the authenticated home screen. This creates a false unauthenticated state for users who already have a saved session and makes startup feel unstable.

## What Changes

- Keep startup in a neutral launch/splash-style gate while saved-session validation and initial authenticated bootstrap are still unresolved.
- Route to the authenticated home screen only after the saved token is validated and required home bootstrap work has completed or settled.
- Route to the login screen only after the app has determined there is no usable saved session, or after the saved token is rejected.
- Prevent the login screen or a separate loading surface from appearing as an intermediate state for users who are already signed in.
- Preserve explicit login behavior: when a user has no valid session, the login screen appears normally and its existing sign-in progress remains local to the login action.

## Capabilities

### New Capabilities
- `authenticated-launch-routing`: Defines how WalkCalc gates startup routing while validating saved authentication and deciding between login and authenticated content.

### Modified Capabilities
- None.

## Impact

- Affected code: `walkcalc-native/Features/Home/HomeViews.swift` and `walkcalc-native/App/WalkcalcStore.swift`.
- Possible related code: startup network warm-up, notification registration sequencing, token refresh handling in `APIClient`, and any debug fixture bootstrap behavior.
- UX: startup remains visually consistent with the splash/login brand state until routing is known; login no longer flashes for valid saved sessions.
- APIs: no backend API changes expected.
- Dependencies: no new external dependencies expected; use existing SwiftUI views and store state.
- Verification: build the native app and manually verify cold launch with no token, valid token, rejected token, network failure during user validation, fixture mode, and explicit login.
