## MODIFIED Requirements

### Requirement: Urgent failures can still interrupt
The system SHALL reserve modal alerts or route-level interruptions for urgent failures that require immediate user awareness, a decision, or renewed authentication. Authentication loss SHALL NOT be suppressed as a recoverable background, pagination, or secondary-load failure.

#### Scenario: Authentication cannot be recovered
- **WHEN** an authenticated request fails because the session cannot be refreshed or the user must sign in again
- **THEN** the system clears local authenticated session state
- **AND** it routes the user to the login screen
- **AND** it does not leave the user on the prior authenticated screen with only a suppressed diagnostic log

#### Scenario: Background refresh loses authentication
- **WHEN** a background refresh, pagination request, search request, or secondary detail refresh receives unrecoverable HTTP 401 or 403
- **THEN** the system treats the failure as session expiration
- **AND** it routes the user to the login screen
- **AND** it does not classify the failure as a silent recoverable refresh failure

#### Scenario: Failure risks data loss
- **WHEN** a network or server failure leaves user-entered data at risk of being lost
- **THEN** the system may interrupt the user before dismissing or replacing the current editing context
- **AND** it preserves the user's draft when possible

#### Scenario: User decision is required
- **WHEN** recovery from a failed operation requires an explicit user choice
- **THEN** the system may present a modal confirmation or alert scoped to that decision
