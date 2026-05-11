# embedded-profile-navigation Specification

## Purpose
Define how the native app opens hong97 profile surfaces in an embedded context and how the profile page hides global navigation.

## Requirements

### Requirement: Native profile opens embedded hong97 page
The native client SHALL open the hong97 SSO profile page with `hideNavbar=1` when presenting the profile inside the app.

#### Scenario: Profile URL includes embed parameter
- **WHEN** the user opens the profile page from the native client
- **THEN** the web URL contains `hideNavbar=1`
- **AND** the page is shown inside the app's existing profile web container

### Requirement: Profile page hides navbar for embed parameter
The hong97 SSO profile page SHALL hide global navigation when `hideNavbar=1` is present.

#### Scenario: Embedded profile hides navbar
- **WHEN** an authenticated user opens `/sso/profile?hideNavbar=1`
- **THEN** the profile page renders without the global site navbar or mobile menu affordance
- **AND** the profile content remains available
- **AND** the footer remains visible

#### Scenario: Normal profile keeps navbar
- **WHEN** an authenticated user opens `/sso/profile` without `hideNavbar=1`
- **THEN** the profile page renders with the normal global site navbar behavior
