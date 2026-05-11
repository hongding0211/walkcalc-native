## 1. Shared Formatting Foundation

- [x] 1.1 Add a shared temporal display formatter with explicit compact and full contexts.
- [x] 1.2 Implement recency bucket classification for today, yesterday, current week, current year, and previous year using injectable `now`, `Locale`, and `Calendar`.
- [x] 1.3 Add Chinese and English localized labels/templates for yesterday, current-week weekdays, month/day dates, previous-year dates, and short time output.
- [x] 1.4 Keep `TimeInterval.walkDate` as the timestamp-to-`Date` conversion helper and route user-visible string formatting through the new formatter.

## 2. Coverage

- [x] 2.1 Add deterministic formatter coverage for `zh-Hans` full and compact output across all recency buckets.
- [x] 2.2 Add deterministic formatter coverage for English full and compact output across all recency buckets.
- [x] 2.3 Verify week-boundary behavior with an injected calendar so current-week output is stable.

## 3. Production UI Migration

- [x] 3.1 Migrate group home row `modifiedAt` display to compact temporal formatting.
- [x] 3.2 Migrate archived group row `modifiedAt` display to compact temporal formatting.
- [x] 3.3 Migrate expense list row `createdAt` display from SwiftUI `.time` to compact temporal formatting.
- [x] 3.4 Migrate expense row accessibility timestamp text to full temporal formatting.
- [x] 3.5 Confirm native `DatePicker` controls remain native and only surrounding custom timestamp labels use the shared formatter.

## 4. Design Preview Migration

- [x] 4.1 Replace `GroupsHomeDemo` hard-coded update strings with sample dates rendered through the shared formatter.
- [x] 4.2 Replace `GroupDetailDemo` direct `Date.formatted(...)` temporal labels with the shared formatter where visible.
- [x] 4.3 Ensure design previews still exercise today, yesterday, current-week, current-year, and previous-year examples.

## 5. Cleanup and Verification

- [x] 5.1 Search for remaining user-visible uses of `DateFormatter.walkDate`, `DateFormatter.walkFullDate`, `Text(date, style: .time)`, and direct `Date.formatted(...)`.
- [x] 5.2 Remove or deprecate obsolete temporal formatter helpers that no longer have valid call sites.
- [x] 5.3 Build the app and run available tests or deterministic formatter checks.
- [x] 5.4 Manually inspect compact row examples in Chinese and English to confirm text length stays appropriate.
