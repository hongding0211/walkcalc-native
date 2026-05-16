# theme-surface-colors Specification

## Purpose

Define how WalkCalc uses neutral app backgrounds, surfaces, text, and separators so future accent themes can vary without changing the app's base visual hierarchy.

## Requirements

### Requirement: Light App Canvas Uses Shallow Grayscale
The app SHALL use a shallow grayscale app canvas/background color for production native screens in light mode, while cards and rows use white surfaces.

#### Scenario: Screen uses shared app background
- **WHEN** a production screen renders its root app background in light mode
- **THEN** the background color is a shallow grayscale neutral
- **AND** the screen does not use the previous warm canvas color as the root background

#### Scenario: Sheet or form uses app canvas behind rows
- **WHEN** a sheet, form, or panel exposes app background around list rows or content surfaces in light mode
- **THEN** the exposed background is a shallow grayscale neutral
- **AND** row or form surfaces use white or near-white grayscale surface tokens for hierarchy

### Requirement: Dark App Canvas Uses Pure Black
The app SHALL use pure black as the dark-mode app canvas/background color for production native screens.

#### Scenario: Screen uses shared app background in dark mode
- **WHEN** a production screen renders its root app background in dark mode
- **THEN** the background color is pure black
- **AND** the screen does not use the previous graphite canvas color as the root background

#### Scenario: Sheet or form uses app canvas behind rows in dark mode
- **WHEN** a sheet, form, or panel exposes app background around list rows or content surfaces in dark mode
- **THEN** the exposed background is pure black
- **AND** row or form surfaces may continue using their existing dark surface tokens for hierarchy

### Requirement: Existing Theme Colors Remain Available
The app SHALL preserve existing accent, category, and semantic balance colors while moving neutral visual infrastructure to grayscale.

#### Scenario: Semantic balance color renders
- **WHEN** the app displays receivable, payable, or zero-balance amounts
- **THEN** the existing positive, negative, and neutral text color behavior remains unchanged

#### Scenario: Branded controls render
- **WHEN** a primary action, selected control, navigation tint, or category accent renders
- **THEN** it keeps using the existing accent or semantic token unless the element is a loading indicator

### Requirement: Neutral UI Tokens Use Grayscale
The app SHALL express supporting neutral UI colors with grayscale values rather than warm or colored tints.

#### Scenario: Text hierarchy renders
- **WHEN** primary, secondary, muted, metadata, or placeholder text renders outside semantic accent contexts
- **THEN** the text color uses a grayscale neutral token
- **AND** it does not use a warm brown, beige, or accent-tinted neutral

#### Scenario: Content surfaces render
- **WHEN** cards, list rows, form rows, avatar fallbacks, low-emphasis fills, or glass tint bases render over the app canvas
- **THEN** they use grayscale neutral surface tokens
- **AND** they remain visually distinguishable from the shallow gray light canvas and pure black dark canvas

#### Scenario: Separators and borders render
- **WHEN** rules, dividers, card borders, row separators, or subtle strokes render
- **THEN** they use grayscale neutral tokens
- **AND** they provide enough contrast to preserve scan hierarchy without introducing warm hue

#### Scenario: Semantic color is needed
- **WHEN** an element communicates brand accent, category, positive balance, negative balance, destructive action, or validation meaning
- **THEN** it may use the appropriate non-grayscale semantic color token
- **AND** that semantic color is not reused as a general neutral surface, text, separator, or loading color

### Requirement: Background Token Supports Future Theme Variants
The app SHALL keep canvas/background and neutral color access centralized through shared theme tokens or background helpers so future theme variants can change accents without changing neutral infrastructure behavior.

#### Scenario: Production screen needs app background
- **WHEN** a production SwiftUI screen needs a full-screen app background
- **THEN** it uses the shared background helper or shared canvas token
- **AND** it does not introduce a feature-local hard-coded tinted background

#### Scenario: Theme accent changes later
- **WHEN** a future theme changes accent or semantic colors
- **THEN** the production light app canvas remains shallow grayscale, the production dark app canvas remains pure black, and supporting neutral tokens remain grayscale unless a separate neutral-color requirement changes them

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
