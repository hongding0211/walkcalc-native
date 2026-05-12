## 1. Shared Keyboard Dismissal

- [x] 1.1 Create a shared SwiftUI keyboard dismissal modifier under `walkcalc-native/Shared/UI`.
- [x] 1.2 Move the existing window-level tap recognizer logic out of `RecordEditorView` into the shared helper.
- [x] 1.3 Ensure the recognizer is passive, removes itself on window changes/deinit, ignores taps inside editable text inputs, and supports an optional focus-reset closure.

## 2. Production Surface Integration

- [x] 2.1 Apply the shared modifier to `CreateGroupSheet`, `JoinGroupSheet`, `GroupSettingsSheet`, `AddTemporaryMemberView`, and `AddMemberSearchView`.
- [x] 2.2 Apply the shared modifier to `RecordSearchCanvas`, clearing `isSearchFocused` without clearing the query.
- [x] 2.3 Replace the record editor's private keyboard overlay with the shared modifier, clearing `focusedField` for amount and note.
- [x] 2.4 Re-scan production code for `TextField`, multiline text input, `@FocusState`, and SwiftUI search inputs to confirm no native keyboard surface was missed.

## 3. Verification

- [x] 3.1 Build the app with the project scheme to catch Swift compile issues.
- [x] 3.2 Manually verify tap-outside keyboard dismissal for join group, create group, group settings, add temporary member, add member search, record search, and record editor.
- [x] 3.3 During manual verification, confirm tapped buttons, navigation links, result rows, clear buttons, and date pickers still receive their original taps.
- [x] 3.4 Confirm existing auto-focus, submit, validation, uppercase normalization, draft preservation, and scroll-dismiss behaviors remain unchanged.
