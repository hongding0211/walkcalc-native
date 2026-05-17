## MODIFIED Requirements

### Requirement: Authenticated Content Appears After Saved Session Bootstrap Settles
The system SHALL keep the launch/splash-style resolving surface visible for saved-session users until authenticated startup bootstrap has settled, including required first-screen home data bootstrap.

#### Scenario: Saved token validates successfully
- **WHEN** startup validates a saved token and obtains the user profile
- **THEN** the system continues authenticated startup bootstrap
- **AND** it starts or continues the required first-screen home data bootstrap while the launch resolving surface remains visible
- **AND** it does not route through the login screen

#### Scenario: Required first-screen bootstrap starts before authenticated routing
- **WHEN** startup has a saved token and ledger API mode is enabled
- **THEN** the system requests the authenticated home first group page and home summary before routing to authenticated home content
- **AND** those requests run as part of startup resolution rather than as a visible post-home empty-state refresh

#### Scenario: Required authenticated startup completes
- **WHEN** saved-session validation succeeds and required startup home bootstrap work completes or settles
- **THEN** the system routes to authenticated home content
- **AND** the user does not see a login-page interstitial between splash and home
- **AND** the user does not see a false empty home state before the first-screen home requests have completed or settled

#### Scenario: Authenticated home data refresh fails after valid auth
- **WHEN** saved-session validation succeeds but initial home data refresh fails with a recoverable non-auth failure
- **THEN** the system may route to authenticated home with existing empty or cached state
- **AND** it records the failure according to quiet network feedback rules
- **AND** it does not route to login unless authentication itself is invalid

#### Scenario: First-screen bootstrap detects unrecoverable auth loss
- **WHEN** a required first-screen home request fails because authentication cannot be refreshed or recovered
- **THEN** the system clears unusable authentication state
- **AND** it routes to the login screen
- **AND** it does not route to authenticated home content with stale or empty protected data
