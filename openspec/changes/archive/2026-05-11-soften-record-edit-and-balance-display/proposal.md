## Why

Opening an existing expense currently feels like an immediate edit action: the keyboard appears, and save/cancel controls are shown before the user has expressed intent. Balance surfaces also hide the current user in some places, which makes the group detail summary and the balance detail sheet feel inconsistent and harder to reason about.

## What Changes

- Existing record sheets open in a read-friendly idle state with no automatic keyboard focus.
- Existing record sheets only reveal edit confirmation/cancellation toolbar actions after the user interacts with an editable control.
- New expense creation remains an explicitly editable flow and can keep its current save/cancel affordances.
- Group detail balances include every group participant, including the current user.
- The balances workspace launched from "View details" uses the same member inclusion rule as the group detail balances section.
- Member balance detail pages continue to filter records by the selected member, including the current user when selected.

## Capabilities

### New Capabilities
- `intentional-record-editing`: Covers the idle/editing states and keyboard behavior for existing record editing.
- `complete-balance-member-visibility`: Covers member inclusion rules for balance previews, balance lists, and member balance detail entry points.

### Modified Capabilities

## Impact

- Affected SwiftUI surfaces: `RecordEditorView`, `GroupBalancesSection`, `BalancesRootView`, and balance navigation/detail presentation.
- Affected design-preview surfaces should stay aligned with production behavior where they model record editing or balance lists.
- No API, persistence, or server contract changes are expected.
