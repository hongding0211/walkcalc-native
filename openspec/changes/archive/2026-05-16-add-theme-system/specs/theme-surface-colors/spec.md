## ADDED Requirements

### Requirement: Selectable Themes Preserve Neutral Infrastructure
The app SHALL keep canvas, supporting surfaces, neutral text, separators, and loading indicators governed by neutral infrastructure tokens when the user changes selectable color themes.

#### Scenario: Theme changes in light mode
- **WHEN** the user changes from one supported theme to another in light mode
- **THEN** the app canvas remains the shared shallow grayscale background
- **AND** cards, rows, forms, neutral text, muted text, and separators remain grayscale neutral tokens

#### Scenario: Theme changes in dark mode
- **WHEN** the user changes from one supported theme to another in dark mode
- **THEN** the app canvas remains pure black
- **AND** supporting dark surfaces, neutral text, muted text, and separators remain grayscale neutral tokens

#### Scenario: Accent-owned UI renders after theme change
- **WHEN** the selected theme changes
- **THEN** accent-owned UI may change to the selected theme palette
- **AND** non-accent neutral infrastructure does not adopt the selected theme hue

#### Scenario: Loading indicator renders after theme change
- **WHEN** an indeterminate loading or progress indicator renders under any supported theme
- **THEN** it keeps the shared secondary loading color treatment
- **AND** it does not use the selected theme accent as its tint
