## MODIFIED Requirements

### Requirement: Record search is server-backed with local fallback
The system SHALL search group records on the backend while the native client can temporarily show matching records from already loaded data. The record list route MUST accept structured search conditions that explicitly declare the fields and operator to apply before pagination. The native record search canvas MUST request note text and localized category display name conditions using OR semantics.

#### Scenario: Search uses server result
- **WHEN** the user searches records inside a group detail search canvas
- **THEN** the client requests `/walkcalc/groups/:code/records` with structured search conditions
- **AND** the conditions include note text and localized category display name fields
- **AND** the conditions use OR semantics
- **AND** the server filters records before pagination by applying the requested structured conditions
- **AND** the displayed results are reconciled with the server response when it arrives

#### Scenario: Loaded records provide interim feedback
- **WHEN** the user enters a record search query and local loaded records already match it by note text or localized category display name
- **THEN** the client can display those local matches before the server response arrives

#### Scenario: Fields not requested by the native search do not match
- **WHEN** the native record search canvas sends only note text and localized category display name conditions
- **AND** a record only contains the search query in payer name, participant name, amount display, raw category id, date, location, creator, modifier, or another field not included in the conditions
- **THEN** the record is not returned as a search match

#### Scenario: Note and category matching is OR based
- **WHEN** the native record search canvas sends OR conditions for note text and localized category display name
- **AND** a record note contains the search query
- **THEN** the record is returned as a search match
- **AND** when a record localized category display name contains the search query
- **THEN** the record is returned as a search match

#### Scenario: Unsupported structured search field is rejected
- **WHEN** the client sends a structured record search condition with a field the backend does not support
- **THEN** the server rejects the request with a validation error
- **AND** the server does not silently broaden the search to other fields
