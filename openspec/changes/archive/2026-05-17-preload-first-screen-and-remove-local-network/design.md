## Context

WalkCalc now has an explicit `startupRoute` that keeps startup in a resolving surface until the app knows whether the user must log in or can enter authenticated content. The remaining launch gap is that saved-session validation and first-screen home bootstrap are still treated as separate phases, so valid users can reach home before the first home data request has produced usable state in some paths.

The native client also warms up network access by issuing HEAD requests and starting a Bonjour `NWBrowser` to trigger Local Network permission for local development. That behavior and the matching Info.plist Local Network keys are not needed in production because production talks to `https://hong97.ltd`.

## Goals / Non-Goals

**Goals:**
- Keep login hidden until startup has confirmed that no usable saved session exists.
- Begin first-screen authenticated home bootstrap during saved-session launch resolution so home does not briefly render a false empty state for returning users.
- Keep the startup gate visible until required home bootstrap requests have completed or settled.
- Remove Local Network permission prompts, Bonjour probing, and Local Network plist metadata from production builds.
- Preserve local-development support for loopback or LAN backend workflows in debug builds.

**Non-Goals:**
- Redesign the login screen, SSO WebView, or backend authentication endpoints.
- Change the `/auth/info`, `/walkcalc/home/summary`, or `/walkcalc/groups/my` API contracts.
- Block authenticated routing forever when first-screen home data fails for non-auth reasons.
- Remove debug support for local backend development.

## Decisions

1. **Treat saved-session launch as an auth plus first-screen bootstrap pipeline.**
   When a saved token exists, startup should start validation and required home bootstrap from the resolving route instead of waiting until authenticated content has appeared. The current required first-screen work is the home group first page and home summary when ledger API mode is enabled.

   Rationale: the route gate already exists specifically to prevent misleading intermediate surfaces. Extending that gate through the first-screen request removes the empty-home flash without adding another visible loading state.

   Alternative considered: route to home immediately after `/auth/info` and show an in-screen loading skeleton. That still permits a visible empty or placeholder transition on the first viewport and does not match the existing launch-routing contract.

2. **Let auth validation remain authoritative over routing.**
   First-screen home requests can be started with the saved token, but an auth rejection from `/auth/info` or unrecoverable refresh failure must clear auth state and route to login. Home bootstrap results must not independently mark the user authenticated if validation fails.

   Rationale: preloading should improve startup smoothness, not weaken authentication routing.

   Alternative considered: wait for validation before starting any home request. That is simpler but keeps the avoidable serial delay that causes the flash this change is meant to remove.

3. **Define "settled" as success or classified non-auth failure.**
   If first-screen home bootstrap succeeds, home opens with populated groups and summary. If it fails with a recoverable transport/server error, startup may route to authenticated content with cached or empty state after recording diagnostics. If it fails because authentication cannot be recovered, route to login.

   Rationale: the app should not strand users on the launch surface because a secondary home refresh is temporarily unavailable, but it also should not show authenticated content after auth loss.

   Alternative considered: require home data success before routing. That would make transient network issues look like an app launch hang.

4. **Gate Local Network behavior at build time.**
   Production builds should not import or execute Bonjour local-discovery warm-up code and should not include `NSLocalNetworkUsageDescription`, `NSBonjourServices`, or local-network-only ATS allowances. Debug builds can keep local warm-up behavior and metadata if they are needed for local backend development.

   Rationale: iOS Local Network prompts are user-visible privacy prompts. Shipping the prompt or metadata for a production app that only talks to the public backend creates unnecessary review and user-trust risk.

   Alternative considered: keep the metadata but skip the runtime `NWBrowser` in production. That reduces prompts but still leaves production entitlements/usage strings that imply unsupported local-network behavior.

## Risks / Trade-offs

- [Risk] Starting `/auth/info` and home bootstrap concurrently can duplicate auth-refresh work if the saved access token is expired. -> Mitigation: keep using the existing refresh coordinator so concurrent 401/403 responses serialize through one refresh attempt.
- [Risk] A recoverable first-screen failure could still open to a real empty state. -> Mitigation: only allow this after the request has settled and been classified; successful responses should populate state before routing.
- [Risk] Removing Local Network plist keys from all configurations could break debug devices pointed at a LAN backend. -> Mitigation: keep the keys and Bonjour probing in debug-only configuration, or use build-setting-driven plist preprocessing so release output excludes them.
- [Risk] Build configuration drift could accidentally ship debug Local Network metadata. -> Mitigation: add verification for the release Info.plist and production code path.

## Migration Plan

1. Refactor startup bootstrap so saved-session validation and first-screen home bootstrap run under the resolving route and coordinate their results before setting `.authenticated`.
2. Keep explicit login routing for missing token, rejected validation, and unrecoverable auth-refresh failure.
3. Move Local Network warm-up code and `Network` framework usage behind `#if DEBUG` or an equivalent debug-only build boundary.
4. Split or preprocess Info.plist values so release builds exclude Local Network usage strings, Bonjour services, and local-network-only ATS allowances.
5. Verify debug startup still supports local backend development and release output contains no Local Network prompt path.
