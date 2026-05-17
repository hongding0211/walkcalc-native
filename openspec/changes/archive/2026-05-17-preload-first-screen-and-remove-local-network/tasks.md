## 1. Startup Bootstrap

- [x] 1.1 Refactor `WalkcalcStore.bootstrap()` so saved-session auth validation and required first-screen home bootstrap are coordinated while `startupRoute` remains `.resolving`.
- [x] 1.2 Start the home first page and home summary requests during saved-session startup when a token exists and ledger API mode is enabled.
- [x] 1.3 Ensure auth validation remains authoritative: missing token, rejected token, or unrecoverable auth refresh clears auth state and routes to `.loginRequired`.
- [x] 1.4 Ensure recoverable first-screen home failures settle startup and allow authenticated routing with cached or empty state only after diagnostics are recorded.

## 2. Production Local Network Removal

- [x] 2.1 Gate `Network` framework import and Bonjour `NWBrowser` local-network prompt code behind debug-only compilation or remove it from release builds.
- [x] 2.2 Keep any local backend warm-up behavior debug-only and ensure production warm-up does not trigger Local Network permission prompts.
- [x] 2.3 Split, preprocess, or otherwise configure Info.plist so release builds exclude `NSLocalNetworkUsageDescription`, `NSBonjourServices`, and `NSAllowsLocalNetworking`.
- [x] 2.4 Keep debug builds able to use loopback or LAN development backends when explicitly configured.

## 3. Verification

- [x] 3.1 Verify returning users with a valid saved session do not see login or a false empty home state before first-screen requests complete or settle.
- [x] 3.2 Verify saved-session auth rejection still clears state and routes to login without showing authenticated home.
- [x] 3.3 Verify recoverable first-screen home request failure reaches authenticated content only after failure classification and logging.
- [x] 3.4 Verify release build output contains no Local Network plist keys and production startup does not execute Bonjour/local-discovery code.
- [x] 3.5 Verify debug local backend startup still works with the configured local API and web base URLs.
