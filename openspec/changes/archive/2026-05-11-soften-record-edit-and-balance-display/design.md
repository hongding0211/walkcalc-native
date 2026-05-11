## Context

`RecordEditorView` is shared by new expense creation and existing record editing. It currently focuses the amount field in `.task`, which opens the keyboard immediately for both modes, and always shows cancellation/confirmation toolbar actions. This is appropriate for a new expense, but too assertive when a user opens an existing record to inspect it.

Group balance surfaces also use inconsistent member filters. The group detail balance preview and the balances workspace currently remove the current user from `group.allMembers`, while other parts of the group model still treat the current user as a normal participant with their own balance and related records.

## Goals / Non-Goals

**Goals:**
- Make existing record sheets start in an idle, read-friendly state.
- Keep new expense creation as an explicit editing flow.
- Reveal edit toolbar actions only after the user interacts with an editable field or control.
- Keep persistence explicit: opening a record or entering edit mode MUST NOT update server state until save is tapped.
- Show the same complete participant set, including the current user, in group detail balance previews and the balances workspace.
- Keep member detail record filtering consistent for every member, including the current user.

**Non-Goals:**
- Change the record data model, balance math, settlement calculation, or API payloads.
- Redesign the full record detail sheet into a separate read-only detail screen.
- Change the new expense creation flow beyond preserving its current editable behavior.

## Decisions

1. Track edit intent inside `RecordEditorView`.

   Existing records should initialize with an idle state, while new records initialize as editing. A simple state such as `hasEditIntent` can drive toolbar visibility, keyboard focus, and destructive edit affordances. This is preferable to splitting the sheet into separate view and edit screens because the current form already contains the controls and can remain a single source of validation and submission logic.

2. Remove automatic focus only for existing records.

   The `.task` setup should still default `paidBy` when needed, but it should set `focusedField = .amount` only when `record == nil`. This preserves speed for new expense creation and prevents keyboard pop-up for existing records.

3. Enter editing on user interaction, not on value diffing.

   The sheet should switch into edit mode when a user focuses a text input or interacts with a mutable control such as paid-by, split members, category, date, note, or delete. This matches the desired feeling of "now I intend to edit" and avoids complex baseline comparison before toolbar actions can appear. Validation and submit behavior remain unchanged after edit mode is active.

4. Scope cancel/save to the editing transaction.

   In existing-record edit mode, cancel should abandon unsaved local changes without calling the update API, and save should submit only when the form is valid. The exact cancel presentation can follow the current sheet pattern, but the important contract is that idle viewing has no top save/cancel actions and no persistence side effect.

5. Use `group.allMembers` for balance member lists.

   The preview and the balances workspace should derive from the same complete list so the current user, regular members, and temporary members are all visible through the same mental model. Preview capping can remain, but the source set must include the current user.

6. Treat current-user balance detail as a first-class member detail.

   Selecting the current user should open the same member detail surface and filter records with the same rule: records where that member paid or is included in `forWhom`. If wording would otherwise read awkwardly, a localized self label can be introduced without changing the underlying navigation model.

## Risks / Trade-offs

- Existing record users may need one extra tap before saving an edit -> Mitigate by entering edit mode as soon as any editable control is touched.
- Hiding top actions in idle mode can make dismissal less explicit -> Mitigate by preserving native sheet dismissal and drag indicator behavior.
- Showing the current user can make balance lists longer -> Mitigate by keeping the existing preview cap and "View details" path.
- A self balance row may be visually confused with other members -> Mitigate with clear member naming and, if needed, a localized self label in detail text.
