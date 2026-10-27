## Why

After a date heading scrolls off screen, readers lose the date context for the visible expenses. Restore that context in the native navigation title without coupling continuous scroll updates to ledger filtering or grouping.

## What Changes

- Show the group name above the expense list and the active expense section's localized date at the top of the list viewport.
- Update title state only when the active section changes, isolated from the ledger content.
- Preserve native large-title collapse, pagination, card styling, and existing grouping semantics (including year sections).

## Capabilities

### New Capabilities
- `expense-date-navigation-title`: Efficient, section-aware navigation titles for group details.

### Modified Capabilities
None.

## Impact

Group detail SwiftUI views, focused debug verification, and group detail UX documentation. No backend, dependency, or persistence changes.
