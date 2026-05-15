# quiet-network-error-feedback Specification

## Purpose
Define how WalkCalc classifies, records, and surfaces network or server failures so routine recoverable failures do not interrupt daily app usage.

## Requirements

### Requirement: Recoverable network failures are non-interrupting
The system SHALL NOT present a modal alert for recoverable background or secondary network failures when the current screen can continue showing existing or empty-state content.

#### Scenario: Home refresh fails with cached groups
- **WHEN** the authenticated home screen refreshes groups or summary data and the request fails
- **AND** cached home content is already available
- **THEN** the system keeps the cached content visible
- **AND** it does not present a modal alert for the failed refresh

#### Scenario: Pagination fails
- **WHEN** the user reaches the end of a loaded group, record, or member-record list and the next page request fails
- **THEN** the system keeps the already loaded rows visible
- **AND** it stops the loading state for that page request
- **AND** it does not present a modal alert for the failed pagination request

#### Scenario: Secondary detail refresh fails
- **WHEN** group balances, settlement suggestions, record search, or member-specific records fail to refresh
- **THEN** the system keeps the last available local or cached data visible
- **AND** it does not present a modal alert for that failure

### Requirement: User-initiated failures stay local to the initiating action
The system SHALL surface failed user-initiated network actions in the local context of the action instead of using a generic global network alert.

#### Scenario: Join group request fails
- **WHEN** the user submits a group ID and the join request fails
- **THEN** the join sheet remains open
- **AND** the system displays concise failure feedback inside the join sheet
- **AND** it does not present a global modal "Network issues" alert

#### Scenario: Sheet mutation request fails
- **WHEN** the user submits a create, rename, archive, delete, member, record, or settlement action from a sheet or detail surface and the request fails
- **THEN** the initiating surface remains in a state where the user can retry or cancel
- **AND** the system does not show generic fallback copy such as "Add fail", "Edit fail", or "Network issues"
- **AND** the system only shows local feedback when the failure contains a specific actionable validation or business-rule message
- **AND** it does not present a generic global network alert

#### Scenario: Business rule failure is not treated as transport failure
- **WHEN** the server rejects a user-initiated action with a validation, authorization, settlement-limit, duplicate, or other business-rule message
- **THEN** the system presents that message in the local action context when it is safe and useful
- **AND** it does not replace the message with a generic "Network issues" alert

### Requirement: Urgent failures can still interrupt
The system SHALL reserve modal alerts for urgent failures that require immediate user awareness or a decision.

#### Scenario: Authentication cannot be recovered
- **WHEN** an authenticated request fails because the session cannot be refreshed or the user must sign in again
- **THEN** the system may interrupt the user with a sign-in or session-expired flow
- **AND** the interruption clearly describes the required next action

#### Scenario: Failure risks data loss
- **WHEN** a network or server failure leaves user-entered data at risk of being lost
- **THEN** the system may interrupt the user before dismissing or replacing the current editing context
- **AND** it preserves the user's draft when possible

#### Scenario: User decision is required
- **WHEN** recovery from a failed operation requires an explicit user choice
- **THEN** the system may present a modal confirmation or alert scoped to that decision

### Requirement: Suppressed failures are diagnosable
The system SHALL record diagnostics for suppressed network and server failures without exposing raw transport details to end users.

#### Scenario: Suppressed transport failure is logged
- **WHEN** a transport-level network error is suppressed from user-facing UI
- **THEN** the system records a diagnostic entry with the operation name and failure category
- **AND** it does not include access tokens, request bodies, personal notes, group names, or other sensitive user content

#### Scenario: Server failure is classified
- **WHEN** a server response indicates failure through HTTP status or response envelope fields
- **THEN** the system classifies the failure separately from transport failures
- **AND** the classification is available to the caller deciding whether to stay silent, show local feedback, show a non-blocking notice, or present an urgent alert
