## ADDED Requirements

### Requirement: Native login preserves refreshable session credentials
The system SHALL preserve the backend-issued refresh credential needed by native API calls after a successful SSO login.

#### Scenario: SSO login stores refresh credential for native refresh
- **WHEN** the user completes SSO login in the native app
- **AND** the backend has issued auth cookies that include the refresh credential
- **THEN** the native app stores the current access token for bearer API requests
- **AND** the native app preserves the refresh credential in platform-protected cookie or credential storage
- **AND** the refresh credential is not stored in `UserDefaults`

#### Scenario: Login callback has access token but no refresh credential
- **WHEN** the native SSO callback provides an access token
- **AND** no backend refresh credential is available to preserve
- **THEN** the app may complete the immediate sign-in
- **AND** the session is treated as non-refreshable
- **AND** the next unrecoverable auth rejection routes the user to login

### Requirement: Native requests recover expired access tokens
The system SHALL attempt backend refresh when an authenticated native API request is rejected because the access token is expired or invalid.

#### Scenario: Expired access token refreshes successfully
- **WHEN** a native authenticated request receives HTTP 401 or 403
- **AND** the preserved refresh credential is valid
- **THEN** the native app calls `POST /auth/refreshToken`
- **AND** the backend returns a new access token
- **AND** the native app persists the new access token
- **AND** the original request is retried once with the new access token

#### Scenario: Concurrent requests share one refresh
- **WHEN** multiple native authenticated requests encounter auth rejection at the same time
- **THEN** the native app performs at most one refresh request for that batch
- **AND** all waiting requests use the resulting access token when refresh succeeds

#### Scenario: Retried request is still rejected
- **WHEN** a refresh succeeds
- **AND** the retried authenticated request still receives HTTP 401 or 403
- **THEN** the app treats the session as unrecoverable
- **AND** it clears native auth state
- **AND** it routes to login

### Requirement: Native auth failure clears session and routes to login
The system SHALL use a single unrecoverable-auth path when refresh cannot restore the session.

#### Scenario: Refresh credential is missing
- **WHEN** an authenticated native request receives HTTP 401 or 403
- **AND** the native app cannot send a refresh credential to `/auth/refreshToken`
- **THEN** the app clears the saved access token and user state
- **AND** it clears local ledger caches
- **AND** it routes to the login screen

#### Scenario: Refresh endpoint rejects the session
- **WHEN** the native app calls `/auth/refreshToken`
- **AND** the backend rejects the refresh request
- **THEN** the app clears native auth state
- **AND** it routes to the login screen

#### Scenario: User explicitly logs out
- **WHEN** the user logs out from the native app
- **THEN** the app clears the saved access token
- **AND** it clears preserved auth cookies or refresh credentials for the backend auth host
- **AND** it routes to the login screen

### Requirement: Backend refresh contract remains cookie-based
The system SHALL keep refresh-token issuance and rotation owned by the backend cookie/session contract.

#### Scenario: Valid refresh cookie rotates session
- **WHEN** the native app calls `/auth/refreshToken` with a valid refresh-token cookie
- **THEN** the backend returns a new access token in the response data
- **AND** the backend sets a replacement access-token cookie
- **AND** the backend rotates and sets a replacement refresh-token cookie

#### Scenario: Refresh cookie cannot authorize protected APIs
- **WHEN** a protected API request includes only the refresh-token cookie
- **THEN** the backend rejects the request as unauthorized

#### Scenario: Reused or expired refresh token is rejected
- **WHEN** the native app calls `/auth/refreshToken` with an expired, revoked, or already-rotated refresh token
- **THEN** the backend rejects the refresh request as unauthorized
- **AND** the native app treats the session as unrecoverable
