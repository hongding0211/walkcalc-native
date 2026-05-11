## Context

The native client currently loads groups with `/walkcalc/groups/my?pageSize=100`, then treats that result as the full home data set. Group detail already loads records through a paginated endpoint, but detail search and member-specific balance detail records are derived from `recordsByGroup`, which only contains records the client has already fetched. hong97-ltd profile embedding should use one explicit query contract from the native client.

## Goals / Non-Goals

**Goals:**
- Make home group loading use explicit page/pageSize state and lazy next-page loading.
- Add backend filters for WalkCalc collection access: group name/code search, record text/type/amount search, and participant-specific record filtering.
- Replace the record-list route with a clearer nested group route.
- Let the client use locally loaded data as immediate search fallback while the backend search request is in flight.
- Build profile URLs with `hideNavbar=1` from the native client and make hong97-ltd use that spelling.
- Verify the native flows in a simulator after implementation.

**Non-Goals:**
- Redesign the home or group detail surfaces beyond the controls needed for pagination/search behavior.
- Move records out of the embedded group document or introduce a new database collection.
- Change settlement math, record mutation payloads, or auth behavior.
- Preserve old WalkCalc API paths or old profile query spellings.

## Decisions

1. Use explicit paginated collection endpoints.

   `/walkcalc/groups/my` accepts `page`, `pageSize`, and optional `search`. Record listing moves to `GET /walkcalc/groups/:code/records` with `page`, `pageSize`, optional `search`, and optional `participantId`. A separate member-record endpoint was considered, but the nested records route keeps pagination, authorization, search, and participant filtering in one collection contract.

2. Filter records on the backend before pagination.

   The service loads the authorized group, sorts records by newest first, applies participant/search filters, and then slices the requested page. This preserves current storage while making result counts and pages reflect the requested server-side collection, not whatever the client has already loaded.

3. Keep local search as a temporary display optimization.

   When a search query changes, the client can immediately show matches from already-loaded records while it debounces and fetches the authoritative backend result. The API result replaces the fallback cache for that query. Empty queries use the normal record cache.

4. Track pagination state separately by collection.

   Home groups use page/total state. Group records use page/total for the default record list. Member detail records use their own cache keyed by group and participant. This prevents a member detail page from truncating the main group record list or vice versa.

5. Use one profile navbar query spelling.

   The native app emits `hideNavbar=1`, and the profile page reads `hideNavbar=1`. This keeps the embed contract easy to remember and avoids a permanent dual-spelling branch.

## Risks / Trade-offs

- Filtering embedded record arrays in memory can still be expensive for very large groups -> The existing per-group record limit bounds the work, and this change does not add a migration.
- Group pagination plus client-side archived filtering can make active and archived lists shorter than a full server page -> Lazy loading remains available, and a future archived filter can be added without changing the base pagination contract.
- Search result replacement can feel jumpy if local fallback differs from server matching -> Use the same text/amount fields in client fallback and backend filters where practical.
- Breaking the old record-list route can affect stale clients -> This is acceptable for this change; deploy the hong97-ltd API and native client together.
