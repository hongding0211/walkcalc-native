## ADDED Requirements

### Requirement: Supported App Themes
The app SHALL provide exactly four selectable color themes: system blue, black, yellow, and green.

#### Scenario: Theme list is shown
- **WHEN** the app presents the theme picker
- **THEN** the available choices are shown in this order: system blue, black, yellow, and green
- **AND** each choice has a stable identifier, accessibility label, and visible color preview

#### Scenario: Default theme is needed
- **WHEN** no supported theme preference has been saved
- **THEN** the app uses the system blue theme
- **AND** the system blue theme uses the platform blue accent direction

#### Scenario: Unsupported theme value is encountered
- **WHEN** persisted theme data contains an unknown or no-longer-supported value
- **THEN** the app falls back to the system blue theme
- **AND** the app does not crash or show an empty picker selection

### Requirement: Theme Selection Persists Locally
The app SHALL persist the selected theme locally and restore it across launches.

#### Scenario: User selects a theme
- **WHEN** the user selects a supported theme in the theme picker
- **THEN** the app stores that theme as the selected theme
- **AND** theme-owned UI updates to the selected theme without requiring sign out

#### Scenario: App launches after a theme selection
- **WHEN** the app starts after a user selected a supported theme in a previous session
- **THEN** the previously selected theme is restored before production screens render their accent-owned UI

#### Scenario: Legacy color preference exists
- **WHEN** the app has an older local `themeColor` preference but no new selected theme value
- **THEN** the app maps `blue` to system blue, `green` to green, `gold` to yellow, and unsupported legacy values to system blue

### Requirement: Selected Theme Applies To Explicit Accent-Owned UI
The app SHALL apply the selected theme to explicitly accent-owned UI consistently across production SwiftUI screens without recoloring UI that previously used secondary, tertiary, primary, or inherited default styling.

#### Scenario: Accent-owned SwiftUI element renders
- **WHEN** a production screen renders a primary action, selected control, navigation tint, accent icon, accent badge, or accent-soft fill
- **THEN** that element uses the selected theme's accent palette
- **AND** it does not keep a hard-coded yellow accent unless the selected theme is yellow

#### Scenario: Non-accent UI renders
- **WHEN** a production screen renders text, icons, buttons, navigation affordances, or controls that previously used `.primary`, `.secondary`, `.tertiary`, semantic colors, or inherited default styling
- **THEN** that UI keeps its previous color behavior
- **AND** it does not adopt the selected theme accent through an app-wide or container-wide tint

#### Scenario: Theme changes while app is open
- **WHEN** the user changes the selected theme while the app is running
- **THEN** visible accent-owned SwiftUI UI updates to the newly selected theme
- **AND** non-accent UI keeps its previous default, primary, secondary, tertiary, or semantic color behavior

### Requirement: Theme Picker Is User Accessible
The app SHALL expose theme selection from an existing settings or profile preference surface.

#### Scenario: User opens app preferences
- **WHEN** the user opens the relevant settings or profile preference surface
- **THEN** a theme selection control is available without requiring developer or debug UI

#### Scenario: User reviews theme choices
- **WHEN** the theme selection control is visible
- **THEN** each theme choice shows a color preview without requiring visible text labels
- **AND** each theme choice exposes an accessibility label
- **AND** the currently selected theme is visually indicated

### Requirement: Theme Choice Preserves Semantic Meaning
The app SHALL keep semantic colors separate from selectable accent themes unless a requirement explicitly assigns them to the theme.

#### Scenario: Balance amount renders
- **WHEN** the app displays receivable, payable, or zero-balance amounts under any supported theme
- **THEN** the positive, negative, and neutral balance color behavior remains unchanged

#### Scenario: Category color renders
- **WHEN** the app displays category icons, category chips, or record category color markers under any supported theme
- **THEN** category color behavior remains unchanged unless the element is explicitly an accent-owned selected state

#### Scenario: Destructive or validation state renders
- **WHEN** the app displays destructive, error, or validation feedback under any supported theme
- **THEN** the feedback uses the appropriate semantic color rather than the selected theme accent
