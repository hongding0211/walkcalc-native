## Why

Authenticated launch currently waits until login routing is resolved before the first home data request is fully useful, which can let the authenticated home briefly render an empty state before its first API response settles. Production builds also still contain local-network permission metadata and Bonjour warm-up behavior that is only useful for local development.

## What Changes

- Start the required first-screen home bootstrap as part of saved-session launch resolution once a usable saved session is being validated, so authenticated users enter home only after the initial home API work has completed or settled.
- Keep routing to login only for confirmed missing or unusable authentication; users with a valid saved session must not see login or an empty-home flash as an intermediate state.
- Restrict local-network privacy prompts, Bonjour probing, and local-network plist permissions to development/debug builds.
- Ensure production builds do not issue Local Network permission-triggering requests or include unnecessary Local Network usage strings/services.

## Capabilities

### New Capabilities
- `production-network-permissions`: Defines which network permissions and local-discovery behavior are allowed in production versus development builds.

### Modified Capabilities
- `authenticated-launch-routing`: Tighten saved-session startup so first-screen authenticated home data bootstrap happens before routing to home, preventing an empty-state flash after launch.

## Impact

- Affected native startup flow: `WalkcalcStore.bootstrap`, launch route/state handling, and any first-screen home refresh helpers.
- Affected native networking: `APIClient.warmUpNetworkAccess`, local-network warm-up helpers, and build-configuration gating.
- Affected iOS metadata: `Supporting/Info.plist` and localized InfoPlist strings for Local Network permission keys.
- No backend API contract change is expected.
