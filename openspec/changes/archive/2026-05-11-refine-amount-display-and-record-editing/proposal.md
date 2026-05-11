## Why

Amount presentation is currently too eager to abbreviate values that users can reasonably reach and still need to read exactly, especially in summary cards. Existing record editing also regressed from the intended idle-inspection flow: destructive deletion disappears in idle state, and cancel from edit mode no longer closes the editor.

## What Changes

- Raise compact amount abbreviation so ordinary 1k and 10k-range values remain exact; compact notation is only used for 100,000+ amounts.
- Make amount precision context-aware: summary/detail surfaces that communicate user balances show exact amounts using text scaling, while dense group and record entry rows may keep compact notation at the higher threshold.
- Keep existing record editor detail/edit behavior: existing records open without top save/cancel actions, but their delete action remains available.
- Make cancel from an existing-record edit transaction discard the draft and close the editor sheet.
- Align zero-balance detail presentation with surrounding balance surfaces so a zero amount does not become visually weaker than the external entry point.
- Preserve the existing home/group collection search capability; this change must not remove the main page search UI or its server-backed behavior.

## Capabilities

### New Capabilities
- `contextual-money-display`: Defines exact versus compact money rendering by UI context, the 100,000+ compact threshold, and zero-balance visual parity.

### Modified Capabilities
- `intentional-record-editing`: Existing record delete visibility and cancel behavior are clarified within the idle/edit transaction model.

## Impact

- Affected SwiftUI surfaces include home total balance, group summary balance, group summary rows, balance preview rows, member balance detail summary, expense rows, and settlement rows.
- Affected shared formatting includes `Money.compactDisplay` and the signed money helper(s) used by balance surfaces.
- Affected record editing surface is `RecordEditorView`.
- Existing server-backed group search and record search behavior must remain intact.
