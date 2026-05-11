## Context

The app stores group and record timestamps as Unix milliseconds (`createdAt` and `modifiedAt`) and currently converts them to `Date` through `TimeInterval.walkDate`. User-visible formatting is split across `DateFormatter.walkDate`, SwiftUI `Text(date, style: .time)`, direct `Date.formatted(...)` calls, and hard-coded design playground strings such as `Today`, `Yesterday`, and `May 8`.

This change needs one product rule that can be reused by production views, accessibility labels, and design previews while still allowing narrow rows to choose shorter output. The project already has a lightweight localization layer through `L10n` and localized string tables for `en` and `zh-Hans`.

## Goals / Non-Goals

**Goals:**

- Provide one shared formatter for user-visible temporal strings.
- Classify dates relative to the user's current calendar into today, yesterday, current week, current year, and previous years.
- Support locale-specific Chinese and English output, including Chinese weekday labels such as `周一`.
- Support at least compact and full display contexts so list rows can stay short while detail and accessibility surfaces keep enough information.
- Migrate all current custom temporal display sites to the shared formatter.

**Non-Goals:**

- Changing backend timestamp payloads or the `TimeInterval.walkDate` conversion.
- Replacing native `DatePicker` controls for editing expense dates.
- Adding fuzzy relative phrases such as `3 minutes ago`.
- Adding timezone selection UI; formatting uses the user's current device calendar, locale, and timezone.

## Decisions

1. Add a shared temporal display formatter instead of adding more `DateFormatter` statics.

   The formatter should live in shared app code, for example `Shared/Formatting/TemporalDisplayFormatter.swift`, and expose a small API such as `TemporalDisplay.string(from:context:now:locale:calendar:)`. Keeping it outside individual views makes all call sites use the same bucket logic and makes it testable with injected `now`, `Locale`, and `Calendar`.

   Alternative considered: extend `DateFormatter` with several new static instances. That would still leave bucket selection and context decisions spread across views.

2. Use explicit recency buckets, not `RelativeDateTimeFormatter`.

   The product rules require exact output families: today uses only time, yesterday uses a localized yesterday label plus time, current week uses weekday plus time, current year uses month/day plus optional time, and previous years include the year. `RelativeDateTimeFormatter` is useful for broad natural language but cannot reliably enforce these exact compact/full forms.

   Alternative considered: rely on SwiftUI `Text(date, style:)` or `Date.formatted(...)` at each call site. Those APIs are useful for component formatting, but they do not encode the product's recency policy by themselves.

3. Make display context explicit.

   The formatter should support a compact context for dense list rows and a full context for places that need an unambiguous timestamp. Compact output may omit time for dates before the current week; full output always includes time and includes the year for previous-year dates. The initial mapping should be:

   - Group home rows: compact `modifiedAt`.
   - Archived group rows: compact `modifiedAt`.
   - Expense list rows: compact `createdAt`.
   - Accessibility labels for rows: full `createdAt` or `modifiedAt`.
   - Design playground samples: generated through the formatter rather than hard-coded English date words.

   Alternative considered: each view chooses its own ad-hoc format. That would preserve local flexibility but keep the inconsistency this change is meant to remove.

4. Localize labels and templates deliberately.

   Chinese output should use product labels such as `昨天` and `周一` through localized resources or a small localized weekday table, and Chinese date output should use `M月d日` / `yyyy年M月d日`. English output should use English labels and locale-appropriate month and time conventions such as `Yesterday 2:05 PM`, `Mon 2:05 PM`, `May 8, 2:05 PM`, and `May 8, 2025, 2:05 PM`.

   Alternative considered: use one universal numeric pattern for all locales. That would be shorter to implement but would ignore the requested Chinese/English distinction.

## Risks / Trade-offs

- Week-boundary differences -> Use `Calendar.dateInterval(of: .weekOfYear, for:)` with the active calendar so "current week" follows the user's locale/calendar.
- Device 12-hour/24-hour preferences may vary -> Use locale-aware time formatting for English and explicit `HH:mm` for Chinese where the product requirement expects `xx:xx`.
- Compact rows may hide time for older dates -> Accessibility labels and full contexts must keep the complete timestamp available where the exact time matters.
- Existing design preview data is string-based -> Update the mock model or sample construction so previews exercise the shared formatter without adding production dependencies that make previews brittle.

## Migration Plan

1. Add the shared formatter and localized labels/templates.
2. Add focused unit coverage or preview-checkable examples for all recency buckets in `zh-Hans` and `en`.
3. Replace `DateFormatter.walkDate`, SwiftUI `.time`, and direct `Date.formatted(...)` user-facing call sites with the shared formatter.
4. Update design playground sample strings to come from dates and formatter output.
5. Search for remaining temporal display calls and remove or deprecate obsolete helpers that are no longer used.

## Open Questions

- None. The previous-year format will include year, month, day, and time in full contexts because omitting the month would be ambiguous.
