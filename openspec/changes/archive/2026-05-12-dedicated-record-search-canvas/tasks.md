## 1. Backend Search Contract

- [x] 1.1 Add structured search condition parsing for `GET /walkcalc/groups/:code/records`, preserving page, pageSize, and participantId behavior.
- [x] 1.2 Validate structured search fields and reject unsupported fields instead of silently broadening search.
- [x] 1.3 Implement OR matching across requested note and localized category-name conditions before pagination totals are calculated.
- [x] 1.4 Ensure scalar legacy search behavior is either preserved for callers that still use it or intentionally migrated according to backend compatibility requirements.
- [x] 1.5 Add or update backend tests for structured note matches, category-name matches, OR matching, filtered pagination totals, unsupported-field validation, and fields not included in conditions not matching.

## 2. Native Search Data

- [x] 2.1 Add a native representation for record search conditions that can encode the canvas query as note/category-name OR matching.
- [x] 2.2 Update `WalkcalcStore` local record fallback matching to use only record notes and localized category display names for the canvas search.
- [x] 2.3 Send structured note/category-name OR search conditions to the backend while keeping server-backed search cache and pagination behavior.
- [x] 2.4 Add or update fixture/debug data so note and category-name search behavior can be manually verified.

## 3. Native Search Canvas

- [x] 3.1 Remove inline record search filtering from the normal `GroupView` detail layout.
- [x] 3.2 Add a dedicated record search canvas opened from the group detail search control as a large system sheet without using navigation push.
- [x] 3.3 Auto-focus the search field when the canvas opens where SwiftUI/platform behavior permits.
- [x] 3.4 Add prompt copy that communicates notes and categories as the supported searchable fields.
- [x] 3.5 Keep the empty-query state blank, with no category suggestions, recent searches, recommended terms, or other pre-query suggestions.
- [x] 3.6 Render search results using the existing expense row presentation and support loading additional result pages.
- [x] 3.7 Open the existing record editor when a search result is selected, preserving current edit/delete/save/cancel behavior.
- [x] 3.8 Ensure dismissing search returns to the same unfiltered group detail page.

## 4. Verification

- [x] 4.1 Verify normal group detail load, pull-to-refresh, and load-more behavior still work without search.
- [x] 4.2 Verify structured searches by note and localized category name return matching records from the backend.
- [x] 4.3 Verify searches by payer, participant, amount, raw category id, date, and location do not return matches unless those fields are explicitly included in structured conditions or the note/category name also matches.
- [x] 4.4 Verify local fallback and backend results do not visibly disagree for the same loaded records.
- [x] 4.5 Verify the search canvas shows no suggestions before typing or after clearing the query.
- [x] 4.6 Run the relevant native build/tests and backend tests for the touched search behavior.
