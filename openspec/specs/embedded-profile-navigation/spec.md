# embedded-profile-navigation Specification

## Purpose
Define how the native app opens hong97 profile surfaces in an embedded context and how the profile page derives embedded behavior from a source configuration.

## Requirements

### Requirement: Native profile opens embedded hong97 page
The native client SHALL open the hong97 SSO profile page with `source=walkcalc` when presenting the profile inside the app.

#### Scenario: Profile URL includes source parameter
- **WHEN** the user opens the profile page from the native client
- **THEN** the web URL contains `source=walkcalc`
- **AND** the page is shown inside the app's existing profile web container

### Requirement: Profile page applies source configuration
The hong97 SSO profile page SHALL derive embedded behavior from the configured `source`.

#### Scenario: Embedded profile applies WalkCalc behavior
- **WHEN** an authenticated user opens `/sso/profile?source=walkcalc`
- **THEN** the profile page renders without the global site navbar or mobile menu affordance
- **AND** the profile content remains available
- **AND** the page hides its web logout button
- **AND** account deletion success remains on a deleted-account confirmation state instead of redirecting to the public home page

#### Scenario: Normal profile keeps default behavior
- **WHEN** an authenticated user opens `/sso/profile` without a configured `source`
- **THEN** the profile page renders with the normal global site navbar behavior
- **AND** the profile page keeps its web logout button
