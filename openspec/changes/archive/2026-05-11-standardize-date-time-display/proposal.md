## Why

The app currently formats dates and times in several local ways, which makes group updates, archived groups, expense rows, accessibility labels, and design previews inconsistent across recency ranges and languages. Standardizing temporal display now gives every surface a predictable rule set while leaving each UI context room to choose a compact or complete variant.

## What Changes

- Introduce a shared, localized temporal display capability for user-visible `Date` and millisecond timestamp values.
- Define recency-aware formats for today, yesterday, the current week, the current year, and previous years.
- Support context-specific display lengths so compact list rows can omit unnecessary detail while detail, edit, accessibility, and audit-like surfaces can show fuller timestamps.
- Migrate all existing app and design-preview temporal display sites to the shared capability.
- Preserve native date picking behavior for editing expense dates while standardizing any custom labels around it.

## Capabilities

### New Capabilities

- `localized-temporal-display`: User-visible date and time strings are formatted by locale, recency bucket, and display context.

### Modified Capabilities

- None.

## Impact

- Affected code includes shared model/date helpers, localization utilities and strings, group home rows, archived-group rows, group expense rows, expense-row accessibility labels, and design playground samples.
- No backend API or data model changes are expected; existing `createdAt` and `modifiedAt` millisecond timestamps remain the inputs.
- Tests or previews should cover Chinese and English output, all recency buckets, and compact versus full display contexts.
