## ADDED Requirements

### Requirement: Shared Temporal Formatter
The system SHALL provide a shared formatter for every user-visible date or time string derived from `Date`, `createdAt`, or `modifiedAt` values.

#### Scenario: Production row uses shared formatter
- **WHEN** a group row, archived group row, or expense row renders a timestamp
- **THEN** the visible timestamp is produced by the shared temporal formatter

#### Scenario: Accessibility label uses shared formatter
- **WHEN** an accessibility label includes a record or group timestamp
- **THEN** the timestamp text is produced by the shared temporal formatter in a full context

### Requirement: Recency Bucket Classification
The system SHALL classify each timestamp against the active calendar and current time into exactly one of these buckets: today, yesterday, current week, current year, or previous year.

#### Scenario: Today bucket
- **WHEN** the timestamp and current time fall on the same calendar day
- **THEN** the timestamp is classified as today

#### Scenario: Yesterday bucket
- **WHEN** the timestamp falls on the calendar day immediately before the current day
- **THEN** the timestamp is classified as yesterday

#### Scenario: Current week bucket
- **WHEN** the timestamp is not today or yesterday and falls within the active calendar's current week
- **THEN** the timestamp is classified as current week

#### Scenario: Current year bucket
- **WHEN** the timestamp is outside the current week and falls within the active calendar's current year
- **THEN** the timestamp is classified as current year

#### Scenario: Previous year bucket
- **WHEN** the timestamp falls before the active calendar's current year
- **THEN** the timestamp is classified as previous year

### Requirement: Full Context Formatting
The system SHALL provide a full display context that keeps time information for every recency bucket and includes the year for previous-year timestamps.

#### Scenario: Chinese full formatting
- **WHEN** the active locale is `zh-Hans` and the full context formats timestamps at 14:05
- **THEN** today renders as `14:05`, yesterday renders as `昨天 14:05`, current week renders as `周x 14:05`, current year renders as `M月d日 14:05`, and previous year renders as `yyyy年M月d日 14:05`

#### Scenario: English full formatting
- **WHEN** the active locale is English and the full context formats timestamps at 2:05 PM
- **THEN** today renders as `2:05 PM`, yesterday renders as `Yesterday 2:05 PM`, current week renders as `Mon 2:05 PM`, current year renders as `May 8, 2:05 PM`, and previous year renders as `May 8, 2025, 2:05 PM`

### Requirement: Compact Context Formatting
The system SHALL provide a compact display context for dense UI locations that may omit time for timestamps outside the current week.

#### Scenario: Chinese compact formatting
- **WHEN** the active locale is `zh-Hans` and the compact context formats timestamps at 14:05
- **THEN** today renders as `14:05`, yesterday renders as `昨天 14:05`, current week renders as `周x 14:05`, current year renders as `M月d日`, and previous year renders as `yyyy年M月d日`

#### Scenario: English compact formatting
- **WHEN** the active locale is English and the compact context formats timestamps at 2:05 PM
- **THEN** today renders as `2:05 PM`, yesterday renders as `Yesterday 2:05 PM`, current week renders as `Mon 2:05 PM`, current year renders as `May 8`, and previous year renders as `May 8, 2025`

### Requirement: Dense Context Formatting
The system SHALL provide a dense display context for the narrowest row metadata columns where compact context labels are still too wide.

#### Scenario: Chinese dense formatting
- **WHEN** the active locale is `zh-Hans` and the dense context formats timestamps at 14:05
- **THEN** today renders as `14:05`, yesterday renders as `昨天 14:05`, current week renders as `周x 14:05`, current year renders as `M月d日`, and previous year renders as `yyyy年M月d日`

#### Scenario: English dense formatting
- **WHEN** the active locale is English and the dense context formats timestamps at 2:05 PM
- **THEN** today renders as `2:05 PM`, yesterday renders as `Yest 2:05 PM`, current week renders as `Mon 2:05 PM`, current year renders as `May 8`, and previous year renders as `May 8, 2025`

### Requirement: Locale-Specific Labels
The system SHALL localize relative labels, weekday labels, date order, month labels, and time style for Chinese and English.

#### Scenario: Chinese labels
- **WHEN** the active locale starts with `zh`
- **THEN** the formatter uses `昨天` for yesterday and `周日`, `周一`, `周二`, `周三`, `周四`, `周五`, or `周六` for current-week weekdays

#### Scenario: English labels
- **WHEN** the active locale does not start with `zh`
- **THEN** the formatter uses English labels such as `Yesterday` and abbreviated weekdays such as `Mon`

### Requirement: Context Mapping
The system SHALL use the compact context for dense visual rows and the full context where exact timestamp information is necessary.

#### Scenario: Dense rows use compact context
- **WHEN** group home rows and archived group rows render timestamps
- **THEN** they use compact temporal formatting

#### Scenario: Narrow expense rows use dense context
- **WHEN** expense list rows render timestamps in the trailing amount/time column
- **THEN** they use dense temporal formatting

#### Scenario: Exact timestamp surfaces use full context
- **WHEN** accessibility labels, detail metadata, or other non-dense timestamp text render timestamps
- **THEN** they use full temporal formatting

#### Scenario: Native date picker remains native
- **WHEN** the expense editor displays the editable date control
- **THEN** the native `DatePicker` behavior remains unchanged unless a surrounding custom timestamp label is rendered

### Requirement: Complete Migration
The system MUST remove ad-hoc user-visible temporal formatting from current app and design-preview surfaces after the shared formatter exists.

#### Scenario: Existing Swift formatting calls are migrated
- **WHEN** the implementation is complete
- **THEN** user-visible uses of `DateFormatter.walkDate`, `DateFormatter.walkFullDate`, SwiftUI `Text(date, style: .time)`, and direct `Date.formatted(...)` are either removed or limited to non-user-visible implementation details

#### Scenario: Design playground samples are migrated
- **WHEN** design playground group or expense samples render update dates
- **THEN** their displayed dates are generated from sample `Date` values through the shared formatter instead of hard-coded strings like `Today`, `Yesterday`, or `May 8`

### Requirement: Testable Time Reference
The system SHALL allow tests and previews to provide a fixed current time, locale, and calendar to the shared formatter.

#### Scenario: Fixed now in tests
- **WHEN** a test formats the same timestamp with a fixed `now`, locale, and calendar
- **THEN** the formatter returns deterministic output for the expected recency bucket
