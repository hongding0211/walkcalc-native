## ADDED Requirements

### Requirement: Navigation title follows the active expense section
The group detail page SHALL show the localized date/year label of the expense section at the top of its visible scroll area, and SHALL show the group name while the overview occupies that area. It MUST preserve the native navigation title and collapse behavior.

#### Scenario: Forward and reverse scrolling
- **WHEN** another date section reaches the top of the visible area in either direction
- **THEN** the title changes to that section's heading
- **AND** returning to the overview restores the group name

#### Scenario: Long section
- **WHEN** a section's heading is offscreen but its records still occupy the top of the visible area
- **THEN** the title continues to identify that section

#### Scenario: Replaced or empty records
- **WHEN** filtering or deleting records removes the active section
- **THEN** the title does not retain a removed section's date

#### Scenario: Appended records or sheet return
- **WHEN** records are appended or an expense sheet closes
- **THEN** the title still reflects the current viewport without forcing a scroll to another section

### Requirement: Scroll-driven updates have bounded scope
The title feature MUST avoid per-record geometry collection and MUST NOT publish continuous offsets into GroupView or WalkcalcStore. Scrolling within one section SHALL NOT trigger ledger filtering or regrouping through title-state updates.

#### Scenario: Same-section scrolling
- **WHEN** the user scrolls repeatedly within a date section
- **THEN** the date selection remains unchanged
- **AND** title tracking does not trigger record filtering or section rebuilding
