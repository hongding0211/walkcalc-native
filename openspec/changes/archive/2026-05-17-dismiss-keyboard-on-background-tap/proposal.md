## Why

Several screens accept keyboard input but only the record editor has a bespoke tap-to-dismiss layer. Users should be able to hide the keyboard consistently by tapping empty space anywhere keyboard input appears, especially on sheets and search flows where the keyboard can obscure the next action.

## What Changes

- Add a shared keyboard dismissal behavior for SwiftUI screens that host `TextField`, multiline text input, or search input.
- Apply the behavior across production input surfaces, including create/join group, group settings, member search, temporary member creation, record search, and record editing.
- Preserve normal control interaction: tapping buttons, navigation links, list rows, date pickers, segmented controls, and text fields must continue to work while dismissing only when appropriate.
- Replace the one-off record-editor tap recognizer with the shared implementation.
- Keep existing submit, validation, focus, and auto-focus behavior intact.

## Capabilities

### New Capabilities
- `keyboard-dismissal`: Defines consistent keyboard dismissal behavior for all app input surfaces.

### Modified Capabilities
- None.

## Impact

- Affected code: shared UI helpers under `walkcalc-native/Shared/UI`, production views in `walkcalc-native/Features/Home` and `walkcalc-native/Features/Groups`.
- APIs: no backend or public API changes.
- Dependencies: no new external dependencies expected.
- Verification: targeted simulator/manual checks for each keyboard entry point and a build/test pass for the native app.
