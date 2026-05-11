# contextual-money-display Specification

## Purpose
Define how money amounts choose between exact and compact display across balance summaries, detail headers, and dense entry rows.
## Requirements
### Requirement: Compact money uses a high-value threshold
The system SHALL render compact money notation only when the absolute major-unit amount is at least 100,000.

#### Scenario: Thousand-range amount stays exact
- **WHEN** an amount is 1,000 or greater but less than 100,000 in absolute major-unit value
- **THEN** compact money formatting returns the exact grouped amount with two decimal places
- **AND** the amount is not abbreviated with a compact suffix

#### Scenario: Hundred-thousand amount can compact
- **WHEN** an amount is at least 100,000 in absolute major-unit value
- **THEN** compact money formatting may use the locale-appropriate compact suffix
- **AND** the sign and currency prefix remain correct at the call site

### Requirement: Balance summary surfaces show exact money
The system SHALL show exact signed money values on balance summary and detail surfaces where the user needs precise account state.

#### Scenario: Home total balance is exact
- **WHEN** the home summary card displays Total balance
- **THEN** it renders the full signed amount with two decimal places
- **AND** it uses text scaling to preserve the card layout instead of abbreviating the value

#### Scenario: Group my balance is exact
- **WHEN** the group detail summary card displays My balance
- **THEN** it renders the full signed amount with two decimal places
- **AND** it uses text scaling to preserve the card layout instead of abbreviating the value

#### Scenario: Member balance detail is exact
- **WHEN** a member balance detail header displays the selected member balance
- **THEN** it renders the full signed amount with two decimal places
- **AND** it does not abbreviate 1,000, 10,000, or 100,000+ values

### Requirement: Dense entry rows may use compact money
The system SHALL allow dense group, record, balance preview, and settlement entry rows to use compact money formatting at the shared high-value threshold.

#### Scenario: Group entry row keeps dense layout
- **WHEN** a group entry row displays a user's balance
- **THEN** it may use compact signed money formatting
- **AND** values below 100,000 major units remain exact

#### Scenario: Record entry row keeps dense layout
- **WHEN** a record entry row displays the paid amount
- **THEN** it may use compact money formatting
- **AND** values below 100,000 major units remain exact

### Requirement: Zero balance detail keeps primary amount emphasis
The system SHALL render a zero balance in member balance detail with the same amount emphasis as the surrounding balance entry point.

#### Scenario: Zero detail balance is not visually muted
- **WHEN** a user opens a member balance detail whose balance is zero
- **THEN** the balance amount uses the primary balance amount emphasis for that detail header
- **AND** it is not rendered with a weaker muted amount color solely because the value is zero
