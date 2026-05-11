# dedicated-record-search-canvas Specification

## Purpose
Define the native record search presentation for group detail pages as a transient, focused search canvas that keeps normal group detail content unfiltered.

## Requirements

### Requirement: Record Search Opens In A Dedicated Transient Canvas
The system SHALL open group record search in a dedicated search canvas from the group detail page using a system sheet with a large presentation detent and without pushing a new destination onto the group detail navigation stack.

#### Scenario: User opens record search
- **WHEN** the user activates search from a group detail page
- **THEN** the system presents a dedicated record search canvas in a system sheet over the current group context
- **AND** the group detail navigation stack is not pushed to a new destination
- **AND** dismissing search returns the user to the same group detail page

#### Scenario: Search canvas starts ready for input
- **WHEN** the record search canvas appears
- **THEN** the search field is visible
- **AND** the search field is focused when the platform can focus it without disrupting presentation

### Requirement: Group Detail Remains Unfiltered Outside Search
The system SHALL keep the normal group detail content independent from active record search queries.

#### Scenario: Search does not repurpose group detail sections
- **WHEN** the user searches records
- **THEN** search results are displayed inside the dedicated record search canvas
- **AND** the group summary, balances, and normal expenses sections are not transformed into search result UI

#### Scenario: Dismissing search restores normal detail view
- **WHEN** the user dismisses the record search canvas after entering a query
- **THEN** the group detail page displays its normal unfiltered expenses list
- **AND** the previous search query does not continue filtering the group detail page

### Requirement: Search Results Support Existing Record Editing
The system SHALL allow a record selected from search results to open the existing record editor flow inside the search presentation.

#### Scenario: User selects a search result
- **WHEN** the user taps a record in the search results
- **THEN** the system opens the existing record editor for that record within the search canvas navigation stack
- **AND** the system does not dismiss search and present a separate editor sheet
- **AND** the selected record uses the same edit, delete, save, and cancel behavior as records opened from the normal expense list

### Requirement: Search Canvas Uses Clear Search Scope Copy
The system SHALL communicate that record search supports notes and categories only.

#### Scenario: Search field describes searchable content
- **WHEN** the record search canvas displays its search field
- **THEN** the placeholder or prompt identifies notes and categories as searchable content

### Requirement: Search Canvas Does Not Show Suggestions
The system SHALL NOT show category suggestions, recent searches, recommended terms, or other pre-query suggestions in the record search canvas.

#### Scenario: Search opens before query entry
- **WHEN** the record search canvas appears before the user enters a query
- **THEN** the system shows no category suggestions
- **AND** the system shows no recent searches
- **AND** the system shows no recommended search terms

#### Scenario: Empty query after clearing text
- **WHEN** the user clears the search query
- **THEN** the system returns to an empty search state without suggestions
