# keyboard-dismissal Specification

## Purpose

Define consistent tap-outside keyboard dismissal for native SwiftUI input surfaces without breaking the original tapped control behavior.

## Requirements

### Requirement: Background taps dismiss keyboard input
The app SHALL dismiss the software keyboard when the user taps outside the active text input on any native SwiftUI screen that contains editable keyboard input.

#### Scenario: Dismiss from form blank area
- **WHEN** a form sheet has an active text field and the user taps a non-input area of the form or surrounding sheet content
- **THEN** the active text field loses focus and the keyboard is dismissed

#### Scenario: Dismiss from custom search canvas
- **WHEN** the record search canvas search field is focused and the user taps empty canvas or result-list space outside the field
- **THEN** the search field loses focus and the keyboard is dismissed without clearing the query

#### Scenario: Dismiss from record editor
- **WHEN** the record editor amount or note field is focused and the user taps outside editable text input
- **THEN** the focused editor field is cleared and the keyboard is dismissed

### Requirement: Keyboard dismissal preserves normal interactions
The app SHALL preserve the original behavior of controls that are tapped while the keyboard is visible, while also dismissing the keyboard when the tap starts outside editable text input.

#### Scenario: Tapping a button while keyboard is visible
- **WHEN** a button, toolbar action, clear button, or inline action is tapped while a text field is focused
- **THEN** the button action still runs and the keyboard is dismissed if the tap did not start inside editable text input

#### Scenario: Tapping navigation while keyboard is visible
- **WHEN** a navigation link, list row, or selectable result is tapped while a text field is focused
- **THEN** the navigation or selection still occurs and the keyboard dismissal gesture does not block the tap

#### Scenario: Tapping the active input
- **WHEN** the user taps inside the active text field or multiline text input
- **THEN** the field remains editable and the keyboard dismissal gesture does not resign focus

### Requirement: Keyboard dismissal is consistently applied to input surfaces
The app SHALL apply the shared keyboard dismissal behavior to all native production SwiftUI surfaces that host editable keyboard input.

#### Scenario: Production input surface coverage
- **WHEN** the user opens create group, join group, group settings, add temporary member, add member search, record search, or record editor flows
- **THEN** each flow supports tap-outside keyboard dismissal

#### Scenario: Existing keyboard behavior remains intact
- **WHEN** an input surface currently auto-focuses, validates on submit, uppercases text, preserves draft text, or dismisses keyboard by scrolling
- **THEN** those behaviors remain unchanged after adding tap-outside dismissal
