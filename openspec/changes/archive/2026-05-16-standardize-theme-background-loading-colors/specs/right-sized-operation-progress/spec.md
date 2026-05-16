## ADDED Requirements

### Requirement: Loading Indicators Use Secondary Color
The system SHALL render all visible indeterminate loading and progress indicators with SwiftUI `.secondary` coloring.

#### Scenario: Initial content loading indicator renders
- **WHEN** a screen or section shows an initial content loading `ProgressView`
- **THEN** the progress indicator uses `.secondary` as its tint
- **AND** it does not use the app accent color or a feature-specific theme color

#### Scenario: Submission progress indicator renders
- **WHEN** a toolbar, sheet, form, or inline confirmation action replaces its normal label or icon with a pending `ProgressView`
- **THEN** the progress indicator uses `.secondary` as its tint
- **AND** the action remains in its existing confirmation placement

#### Scenario: Pagination or search progress indicator renders
- **WHEN** a list continuation point, search results area, or compact content-scoped loader shows pending work
- **THEN** the progress indicator uses `.secondary` as its tint
- **AND** any accompanying text may continue using the existing secondary or muted text style

#### Scenario: Parent view has accent tint
- **WHEN** a parent view applies the app accent through `.tint(SoftLedgerTheme.accent)` or UIKit appearance tint
- **THEN** nested loading indicators still render with `.secondary`
- **AND** they do not inherit the accent tint
