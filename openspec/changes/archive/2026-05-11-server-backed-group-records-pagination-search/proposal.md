## Why

WalkCalc currently treats several server-backed data sets as if they were small local collections: the group list defaults to fetching 100 records, search filters only what has already been loaded, and member-specific record history is filtered on the client after fetching group detail. These shortcuts can hide data, waste payload, and make the native client behave differently as group and record counts grow.

## What Changes

- Group list loading uses an explicit paginated API contract instead of relying on a large default fetch size.
- Group search is backed by an API query while still allowing the client to use already-loaded data for responsive interim feedback.
- Member-specific record history in group detail is queried by the backend with pagination instead of being derived only from the currently fetched detail payload.
- The native profile entry opens the hong97.ltd profile page with the `hideNavbar` embed parameter so hong97 site navigation is hidden inside the client context.
- hong97-ltd server/frontend behavior is updated alongside the native client so the API and embedded profile page match the client contract.

## Capabilities

### New Capabilities
- `walkcalc-server-backed-collection-access`: Covers paginated group browsing, API-backed group search, and backend-filtered member record queries for WalkCalc.
- `embedded-profile-navigation`: Covers native-to-hong97 profile navigation that hides the hong97 site shell when embedded in the client.

### Modified Capabilities

## Impact

- Affected native code: WalkCalc API client models/services and SwiftUI group/profile surfaces that load groups, search groups, and open member record/profile views.
- Affected hong97-ltd code: WalkCalc server controllers/services/DTOs and profile page layout/query handling.
- API contracts change for group list/search and member record lookup; existing detail pagination should remain compatible.
- Verification requires backend tests plus simulator E2E coverage for group pagination/search, member records, and profile embedding.
