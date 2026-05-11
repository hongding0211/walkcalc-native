## ADDED Requirements

### Requirement: Groups are loaded through paginated server access
The system SHALL load the current user's WalkCalc groups through a paginated API request with explicit `page` and `pageSize` query values.

#### Scenario: Initial group page loads
- **WHEN** the native client opens the authenticated home screen
- **THEN** it requests the first group page from the server with an explicit page size
- **AND** it renders the groups returned by that page
- **AND** it stores the server pagination total for lazy loading

#### Scenario: Next group page loads
- **WHEN** the user reaches the end of the currently loaded group list and the server total indicates more groups exist
- **THEN** the native client requests the next group page
- **AND** it appends newly returned groups without replacing previously loaded groups

### Requirement: Group collection search is server-backed
The system SHALL allow the current user's group collection to be searched by the server using the same paginated response shape as normal group loading.

#### Scenario: Group search request
- **WHEN** the client requests groups with a non-empty search query
- **THEN** the server filters the user's accessible, non-deleted groups before pagination
- **AND** the response total reflects the filtered result set

### Requirement: Group records are loaded through a nested paginated route
The system SHALL expose group records at `GET /walkcalc/groups/:code/records` with `page` and `pageSize` query values.

#### Scenario: Group detail records load
- **WHEN** the native client opens a group detail page
- **THEN** it requests the first records page from `/walkcalc/groups/:code/records`
- **AND** it renders records from the server response
- **AND** it uses the response total to determine whether more records can be loaded

### Requirement: Record search is server-backed with local fallback
The system SHALL search group records on the backend while the native client can temporarily show matching records from already loaded data.

#### Scenario: Search uses server result
- **WHEN** the user searches records inside a group detail page
- **THEN** the client requests `/walkcalc/groups/:code/records` with the search query
- **AND** the displayed result is replaced by the server response when it arrives

#### Scenario: Loaded records provide interim feedback
- **WHEN** the user enters a record search query and local loaded records already match it
- **THEN** the client can display those local matches before the server response arrives

### Requirement: Member-specific records are server-filtered
The system SHALL support filtering group records by a participant identifier on the backend before pagination.

#### Scenario: Member balance detail loads records
- **WHEN** the user opens a balance detail view for a member or temporary member
- **THEN** the native client requests `/walkcalc/groups/:code/records` with that participant identifier
- **AND** the server returns only records where the participant paid or is included in `forWhom`
- **AND** pagination totals describe the filtered member-specific record set
