## ADDED Requirements

### Requirement: Production Builds Do Not Request Local Network Access
The system SHALL avoid Local Network permission-triggering behavior in production builds.

#### Scenario: Production startup warms network access
- **WHEN** a production build starts network warm-up
- **THEN** the system does not start Bonjour discovery, `NWBrowser`, peer-to-peer browsing, or any other Local Network permission-triggering probe
- **AND** it does not show the iOS Local Network privacy prompt

#### Scenario: Production app uses configured public backend
- **WHEN** a production build uses the default WalkCalc backend configuration
- **THEN** the system uses the public HTTPS backend and web origins
- **AND** it does not require loopback, LAN, Bonjour, or peer-to-peer local networking to launch or authenticate

### Requirement: Production Metadata Excludes Local Network Permissions
The system SHALL exclude local-development-only Local Network permission metadata from production app output.

#### Scenario: Release Info.plist is produced
- **WHEN** the app is built for production or release distribution
- **THEN** the generated app Info.plist does not contain `NSLocalNetworkUsageDescription`
- **AND** it does not contain `NSBonjourServices`
- **AND** it does not contain local-network-only ATS allowances such as `NSAllowsLocalNetworking`

#### Scenario: Debug local backend remains supported
- **WHEN** a debug build is configured for local backend development
- **THEN** the system may include Local Network usage metadata needed by iOS
- **AND** it may run local-network warm-up behavior only in that debug build
- **AND** that behavior is not compiled into or enabled for production builds
