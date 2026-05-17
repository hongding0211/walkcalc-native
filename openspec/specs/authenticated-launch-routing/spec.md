# authenticated-launch-routing Specification

## Purpose

Define how WalkCalc decides what to show during startup while saved authentication is being resolved, so authenticated users do not see the login screen or a separate loading surface as a temporary state.

## Requirements

### Requirement: Startup Has An Explicit Authentication Resolving State
The system SHALL represent launch-time saved-session validation as a distinct resolving state before choosing login or authenticated content.

#### Scenario: App starts and authentication is unresolved
- **WHEN** the app starts and saved-session validation has not reached a terminal result
- **THEN** the system shows a launch/splash-style resolving surface
- **AND** the system does not show the login screen as the resolving surface
- **AND** the resolving surface does not show an explicit progress or loading indicator

#### Scenario: Resolving surface is non-actionable login
- **WHEN** startup authentication is still resolving
- **THEN** the resolving surface does not expose a usable login button
- **AND** it does not tell the user they must log in before that has been determined

### Requirement: Login Appears Only After Authentication Is Known To Be Required
The system SHALL route to login only after determining that no usable saved session is available.

#### Scenario: No saved token exists
- **WHEN** startup finds no saved authentication token
- **THEN** the system routes to the login screen
- **AND** it does not wait for authenticated home data loading

#### Scenario: Saved token is rejected
- **WHEN** startup validates a saved token and the token is unusable
- **THEN** the system clears the unusable authentication state
- **AND** routes to the login screen

#### Scenario: Explicit login starts
- **WHEN** the user is on the login screen and starts SSO sign-in
- **THEN** sign-in progress remains local to the login flow
- **AND** the startup resolving surface is not reused for that explicit login action

### Requirement: Authenticated Content Appears After Saved Session Bootstrap Settles
The system SHALL keep the launch/splash-style resolving surface visible for saved-session users until authenticated startup bootstrap has settled.

#### Scenario: Saved token validates successfully
- **WHEN** startup validates a saved token and obtains the user profile
- **THEN** the system continues authenticated startup bootstrap
- **AND** it does not route through the login screen

#### Scenario: Required authenticated startup completes
- **WHEN** saved-session validation succeeds and required startup home bootstrap work completes or settles
- **THEN** the system routes to authenticated home content
- **AND** the user does not see a login-page interstitial between splash and home

#### Scenario: Authenticated home data refresh fails after valid auth
- **WHEN** saved-session validation succeeds but initial home data refresh fails
- **THEN** the system may route to authenticated home with existing empty or cached state
- **AND** it does not route to login unless authentication itself is invalid

### Requirement: Startup Routing Reaches A Terminal State
The system SHALL avoid leaving startup permanently in the resolving state after bootstrap work has completed or failed.

#### Scenario: Fixture mode startup
- **WHEN** debug fixture mode is active during startup
- **THEN** the system resolves startup routing without waiting for network authentication

#### Scenario: Saved-session validation encounters an error
- **WHEN** startup cannot validate a saved token because of an auth or network error
- **THEN** the system reaches a user-visible terminal state such as login or a retryable launch error
- **AND** it does not remain indefinitely on the resolving surface
