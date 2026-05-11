## Context

Group detail currently attaches SwiftUI `.searchable` directly to the ledger page. The search text lives in `GroupView`, the expense section consumes `store.records(groupId:search:)`, and `WalkcalcStore.searchRecords` calls `GET /walkcalc/groups/:code/records?search=` with local fallback while the server result is loading.

That architecture gives useful server-backed behavior, but the interaction is muddy: summary cards, balances, and normal expenses remain visible while the expense list quietly becomes a search result list. The desired direction is a dedicated iOS-style search canvas that opens from group detail without using navigation push.

## Goals / Non-Goals

**Goals:**
- Give record search a dedicated transient canvas opened from group detail.
- Avoid a `NavigationLink` or navigation-stack push for search entry and exit.
- Focus the search field when the canvas opens so search starts quickly.
- Keep result rows consistent with current expense rows and allow tapping a result to open the existing record editor.
- Keep server-backed pagination and local fallback.
- Make the native record search canvas request only record notes or localized category names with OR semantics.
- Make the backend record search contract structured so future clients can pass explicit search conditions instead of relying on implicit backend field choices.

**Non-Goals:**
- Add global app search, a Search tab, Spotlight indexing, or cross-group search.
- Expose payer, split participant, amount, date, raw category id, group name, location, creator, or modifier search in the first native record search canvas.
- Add advanced filters, tokenized search, date parsing, search history, or pre-query suggestions.
- Redesign the record editor or normal group detail layout beyond replacing the search entry behavior.

## Decisions

1. Use a transient search canvas owned by `GroupView`.

   The group detail search control should toggle a local presentation state and show a dedicated `RecordSearchCanvas` style view in a system sheet using the large detent. The sheet should feel like a focused, temporary task surface, not a new place in the app hierarchy. It must not push a destination onto the navigation stack. This keeps search easy to dismiss and avoids making a temporary lookup feel like a deep destination.

   Alternative considered: a navigation push to a `RecordSearchView`. This would provide a full screen naturally, but it makes search feel heavier and adds stack state for a task the user expects to enter and exit quickly.

   Alternative considered: a custom overlay. This could mimic a bespoke in-place search mode, but it would require more custom keyboard, safe-area, gesture-dismissal, accessibility, and background interaction handling than a system sheet. A system sheet better matches the HIG guidance for a distinct, narrowly scoped task while preserving the previous group context.

2. Move query and result UI into the search canvas.

   The normal group detail page should no longer bind its main layout directly to `searchText`. The search canvas owns the query field, loading/empty states, and the result list. Dismissing the canvas returns the group detail page to its normal, unfiltered state.

   Alternative considered: keep `.searchable` on `GroupView` and conditionally hide summary/balance content while searching. That still couples the main ledger layout to search mode and makes the view harder to reason about.

3. Keep one simple mixed search query.

   In the first native search canvas, a non-empty query matches a record when either the record note contains the query or the localized category display name contains the query. Matching is OR, not AND. Empty record notes do not implicitly match the fallback category title unless the category name itself matches.

   Alternative considered: include payer, participants, amounts, dates, and raw type identifiers. Those fields make the contract harder to explain and risk surprising users with broad matches. The first useful version should be deliberately small.

4. Do not show suggestions before typing.

   The first version should present an empty, focused search canvas until the user enters a query. It must not show category chips, recent searches, recommended terms, or other suggestions before typing. This keeps the search surface minimal and avoids implying that category browsing is a separate feature.

   Alternative considered: show category chips such as Meal, Transport, Shopping, and Hotel before input. Those categories are finite and tappable, but they add another interaction mode that is not needed for the first version.

5. Send structured backend search conditions.

   The backend should stop treating a single scalar `search` value as an implicit bundle of fields. The record list endpoint should accept structured search conditions, encoded in the query string to preserve the existing paginated `GET /walkcalc/groups/:code/records` route. The first native client request should use an object equivalent to:

   ```json
   {
     "operator": "or",
     "conditions": [
       { "field": "note", "query": "coffee" },
       { "field": "categoryName", "query": "coffee" }
     ]
   }
   ```

   The exact wire format can be a URL-encoded JSON value in `search`, for example `search=%7B...%7D`, or an equivalent query representation if the backend already has a structured query parser. The important contract is that fields and operator are explicit, validated, and applied before pagination.

   Alternative considered: keep `search=coffee` and change the backend default matcher to note/category only. That solves this specific UI, but it leaves the same ambiguity for future search surfaces.

6. Align local fallback and backend filtering.

   The client already provides immediate local fallback from loaded records while the server search request is in flight. That fallback should use the same note/category-name matcher as the structured backend search request sent by this canvas. The backend remains authoritative and replaces fallback results when it returns.

   Alternative considered: leave the server broad and narrow only client display. That would make totals and pagination inconsistent because the server could return records the local matcher would not consider valid.

7. Treat category names as localized search terms.

   The app already has category title keys such as `Meal`, `Drink`, `Transport`, and `Ticket`. The native fallback should compare against localized category titles through `L(category.titleKey)`. The backend should use the same display-name vocabulary for the user's language, or an explicit server-side category-name map aligned with app localization.

   Alternative considered: search raw category ids like `food` or `traffic`. Raw ids are implementation details and should not be user-facing search behavior.

## Risks / Trade-offs

- [Risk] Backend category-name localization may not know the user's current language. -> Mitigation: send/use existing language metadata where available, or define a compact server category-name map for supported locales and document fallback behavior.
- [Risk] Removing amount/member search can feel like a regression for people who discovered it accidentally. -> Mitigation: use placeholder text that clearly says notes and categories are searchable.
- [Risk] Modal search can feel too separate if the user only wanted a quick filter. -> Mitigation: auto-focus the search field, keep dismissal obvious, and return directly to the unchanged group detail page.
- [Risk] Local fallback and server results can diverge if the category-name maps differ. -> Mitigation: add tests for note/category matching in both client fixture matching and backend service filtering.

## Migration Plan

1. Add structured record search condition parsing and validation to the backend record list route.
2. Update the native record search canvas request to send note/category-name OR conditions explicitly.
3. Update native local fallback matching to the same note/category-name rule.
4. Replace `GroupView` inline searchable state with the dedicated search canvas presentation.
5. Verify normal group detail loading, structured search result pagination, empty search, and result-to-editor flow.
6. Roll back by restoring the previous `GroupView` `.searchable` binding and scalar `search` request if the dedicated canvas blocks release.

## Open Questions

- None.
