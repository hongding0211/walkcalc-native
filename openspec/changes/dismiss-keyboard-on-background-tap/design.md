## Context

The app is primarily SwiftUI, with input surfaces spread across production flows. Current keyboard handling is inconsistent: `RecordEditorView` has a private `KeyboardDismissTapLayer`, while create/join group, group settings, temporary member, member search, and record search rely on default focus and scrolling behavior. That leaves sheets and custom search canvases with no reliable blank-area tap to dismiss the keyboard.

The existing record-editor layer shows the right direction: a non-cancelling UIKit tap recognizer attached to the hosting window can observe blank taps without blocking SwiftUI controls. The implementation should be promoted to shared UI infrastructure and applied consistently.

## Goals / Non-Goals

**Goals:**
- Provide one shared SwiftUI modifier for tap-to-dismiss keyboard behavior.
- Support all production screens that expose keyboard input.
- Preserve normal tap behavior for controls, navigation, rows, date pickers, menus, and the active input field.
- Keep field-specific `@FocusState`, validation, submit labels, and initial auto-focus behavior unchanged.
- Migrate the existing record-editor-specific keyboard layer into the shared implementation.

**Non-Goals:**
- Redesign forms, search UIs, or sheet layouts.
- Change validation, persistence, networking, or record-editing business rules.
- Add a custom keyboard toolbar or global done button.
- Force dismissal for web-based profile editing, since that is hosted outside the SwiftUI input surfaces covered by this change.
- Update DesignPlayground screens, since they are presentational and not part of the production keyboard contract.

## Decisions

1. Add a shared keyboard dismissal modifier in `Shared/UI`.

   The modifier will expose an API such as `.dismissKeyboardOnBackgroundTap(isActive:)` or `.softLedgerDismissesKeyboardOnTap(isActive:)`. Internally it will host a tiny `UIViewRepresentable` that installs a `UITapGestureRecognizer` on the containing `UIWindow`.

   Rationale: attaching to the window lets forms, scroll views, lists, and custom canvases share the same behavior without layering invisible SwiftUI rectangles over content. This matches the current record editor approach and avoids repeated page-local gesture code.

   Alternative considered: add `.onTapGesture` to every form or background. This is simpler but unreliable for nested `Form`, `List`, `ScrollView`, and UIKit-backed controls, and it risks swallowing row/button taps.

2. Make the recognizer passive and control-safe.

   The recognizer will use `cancelsTouchesInView = false` and a delegate that ignores touches beginning inside text inputs and other editable UIKit views. It should call `endEditing(true)` on the active window, or a supplied focus-reset closure when a view must clear local `@FocusState`.

   Rationale: passive observation lets the original tap continue to buttons, links, list rows, and pickers. Calling UIKit `endEditing` covers fields without needing every screen to expose focus state; optional focus reset keeps screens like `RecordEditorView` and `RecordSearchCanvas` internally consistent.

   Alternative considered: require every input screen to own and clear `@FocusState`. That improves explicitness but creates boilerplate and misses screens where SwiftUI wraps UIKit controls without a dedicated focus binding.

3. Apply the modifier at screen roots that contain text input.

   Production targets include `JoinGroupSheet`, `CreateGroupSheet`, `GroupSettingsSheet`, `AddTemporaryMemberView`, `AddMemberSearchView`, `RecordSearchCanvas`, and `RecordEditorView`.

   Rationale: applying at the root of each input surface keeps the behavior local to screens where it matters and avoids global gesture installation when no keyboard input is present.

4. Keep scroll dismissal as a complement.

   Existing `.scrollDismissesKeyboard(.interactively)` behavior in record editing can remain. The new modifier covers the separate blank-tap case and does not need to replace scroll-based dismissal.

## Risks / Trade-offs

- Gesture recognizer conflicts with SwiftUI or UIKit controls -> keep it passive, delegate-filter input views, and verify buttons/navigation still receive taps.
- Multiple presented sheets each install a recognizer -> the representable tracks its installed window and removes the recognizer on deinit/window change.
- Focus state becomes stale after UIKit `endEditing` -> support optional focus-clearing closures for views that track focus explicitly.
- Empty-area semantics are ambiguous inside dense forms -> treat non-input controls as valid taps that also dismiss while preserving their normal action, because users commonly expect tapping another control to hide the keyboard.

## Migration Plan

1. Move the private keyboard dismissal UIViewRepresentable out of `GroupPanels.swift` into shared UI code.
2. Replace the record editor's private overlay with the shared modifier.
3. Apply the shared modifier to each production input surface found by scanning for `TextField`, multiline text fields, search input, and `@FocusState`.
4. Build the app and manually verify keyboard dismissal on simulator for representative sheets and search flows.
