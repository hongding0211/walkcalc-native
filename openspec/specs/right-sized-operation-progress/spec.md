# right-sized-operation-progress Specification

## Purpose

Define when WalkCalc shows, suppresses, or localizes loading and progress feedback so pending work is understandable without making routine app usage noisy.

## Requirements

### Requirement: Progress Feedback Matches Operation Impact
The system SHALL choose progress feedback based on whether the operation blocks a user-initiated intent, loads visible content, or refreshes usable content in the background.

#### Scenario: User-submitted mutation starts
- **WHEN** a user submits a record, group, member, archive, delete, restore, or settlement action that awaits a network result
- **THEN** the initiating control or initiating surface shows local indeterminate progress
- **AND** the system prevents duplicate submission while the operation is pending

#### Scenario: Background refresh starts with usable content
- **WHEN** the app refreshes content in the background while current content remains usable
- **THEN** the system does not add a modal progress view or success notification
- **AND** successful refreshed content may appear naturally in place

#### Scenario: Instant local action completes
- **WHEN** a user performs an action that completes locally without waiting for remote persistence
- **THEN** the system does not show a progress indicator for that action

### Requirement: Submission Progress Is Local To The Confirmation Action
The system SHALL render submission progress in the same interaction area that initiated the submitted operation when that area remains visible.

#### Scenario: Toolbar confirmation button is pending
- **WHEN** a user taps a toolbar confirmation button that normally displays a `checkmark`
- **THEN** the button replaces the `checkmark` with an indeterminate progress indicator until the operation completes
- **AND** the button remains visually in the confirmation placement

#### Scenario: Pending submit is inaccessible to repeat taps
- **WHEN** a submitted operation is pending
- **THEN** the initiating confirmation action is disabled against repeat activation
- **AND** keyboard submit or other alternate submit paths do not start a duplicate operation

#### Scenario: Assistive status remains understandable
- **WHEN** a confirmation action is showing progress
- **THEN** the action exposes an accessibility label that still identifies the operation being performed

### Requirement: Content Loading Uses Content-Scoped Indicators
The system SHALL use content-scoped progress indicators for content that is visibly loading and not blocking unrelated interaction.

#### Scenario: Initial content is unavailable
- **WHEN** a screen or section cannot yet show meaningful content because its first load is pending
- **THEN** the system may show a progress indicator in the content area
- **AND** it does not present a redundant modal progress overlay for the same load

#### Scenario: Pagination is pending
- **WHEN** a list loads additional rows after already showing existing rows
- **THEN** the system shows loading feedback at the list continuation point
- **AND** existing rows remain visible and interactive when possible

#### Scenario: Search query is pending
- **WHEN** a non-empty search query is debounced or loading remote results
- **THEN** the system may show compact search-scoped progress
- **AND** it does not show progress for an empty query or a cleared search field

### Requirement: Completion Removes Progress Without Redundant Success Feedback
The system SHALL remove transient progress when work completes and avoid redundant success messaging for routine operations.

#### Scenario: Submitted mutation succeeds
- **WHEN** a submitted mutation succeeds
- **THEN** the local progress indicator disappears as part of the resulting content update or surface dismissal
- **AND** the system does not show a routine success toast or alert

#### Scenario: Submitted mutation fails
- **WHEN** a submitted mutation fails
- **THEN** the local progress indicator stops
- **AND** the initiating surface remains available for retry or cancellation

#### Scenario: Background refresh succeeds
- **WHEN** background or pull-to-refresh work succeeds
- **THEN** the system does not show a success message
- **AND** updated content provides the primary feedback when there is visible change

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
