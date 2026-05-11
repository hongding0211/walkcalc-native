## 1. hong97-ltd API

- [x] 1.1 Add group collection search query support to WalkCalc group DTO/service tests.
- [x] 1.2 Replace the old group-record list route with `GET /walkcalc/groups/:code/records`.
- [x] 1.3 Add backend record filtering for `search` and `participantId` before pagination.
- [x] 1.4 Update WalkCalc controller/service tests for the new records route and filtered pagination.

## 2. hong97-ltd Profile

- [x] 2.1 Update the SSO profile page to read `hideNavbar=1`.
- [x] 2.2 Remove reliance on the old `hideNavBar` spelling in profile navbar hiding logic.

## 3. Native Client Data Flow

- [x] 3.1 Update `APIClient` group and record methods to send explicit pagination/search parameters and use the nested records route.
- [x] 3.2 Add group pagination state and lazy next-page loading to `WalkcalcStore` and the home list.
- [x] 3.3 Add server-backed record search with local loaded-record fallback in group detail.
- [x] 3.4 Add member-record caches and backend loading for balance detail pages.
- [x] 3.5 Update the native profile URL to include `hideNavbar=1`.

## 4. Verification

- [x] 4.1 Run hong97-ltd server tests for WalkCalc API behavior.
- [x] 4.2 Build the native app for the configured iOS simulator.
- [x] 4.3 Run the app in simulator and verify group pagination/search, member record detail loading, and embedded profile URL behavior.
