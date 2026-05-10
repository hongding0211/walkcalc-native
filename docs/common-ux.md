# Common UX Specification

This document defines shared interaction rules used across the app. Page-level specs may add local details, but should not redefine these baseline behaviors.

## 1. Native Controls And Buttons

Interactive controls should feel system-native before they feel branded. Prefer Apple-provided SwiftUI controls and styles, then tune hierarchy with placement, labels, and control size.

### Copy Capitalization

- Use sentence case for English UI copy by default.
- Capitalize only the first word and proper nouns:
  - `Add user`
  - `Group settings`
  - `New expense`
  - `Delete expense`
- Keep real names, group names, and product names in their authored capitalization, such as `May Trip`.
- Avoid title case for routine buttons, sheet titles, section labels, alerts, and menu items.

### Button Rules

- Use native `Button` controls for actions.
- Use native button styles before creating custom surfaces:
  - `.plain` for toolbar/menu rows when the container already provides affordance.
  - `.bordered` for secondary actions that need a visible touch target.
  - `.glass` for transparent Liquid Glass actions.
  - `.glassProminent` only for rare, high-emphasis actions.
- Do not recreate Liquid Glass buttons with custom blur, capsule backgrounds, strokes, shadows, or layered overlays.
- Do not apply extra tint to transparent glass buttons unless the action has a strong semantic color.
- Prefer system `controlSize` values to manual padding when adjusting button size.
- Icon buttons should use SF Symbols and native toolbar or button placement.
- Text buttons should use native typography from the button style; avoid custom font/color overrides unless accessibility or hierarchy requires it.

### Liquid Glass Actions

- Use `.glass` or `.glass(.regular)` for secondary or transparent glass actions.
- Use `.glassProminent` for a single primary action inside a local workspace, such as resolving transfers inside the balances sheet.
- Do not use `.glass(.clear)` for a primary action on a quiet, warm background; the effect can become too subtle to read as Liquid Glass.
- Avoid placing important text actions in `.bottomBar` when the system can collapse them into overflow.
- Prefer a floating native button over a custom full-width bottom bar when the action is contextual and local to a sheet.

### Empty-State Actions

- Empty-state primary actions should still use native button styles.
- For the Groups empty state, use a transparent system glass button:
  - `Button { ... } label: { Label("Create group", systemImage: "plus") }`
  - `.buttonStyle(.glass)`
  - `.controlSize(.regular)`
- Do not use `.glassProminent` for this empty-state action.
- Do not wrap the empty-state action in a custom capsule or decorative card.

### Bottom Search And Creation

Pages that need both search and a primary creation action should prefer the native iOS 26 bottom toolbar pattern.

Rules:

- Use `DefaultToolbarItem(kind: .search, placement: .bottomBar)` for the search field.
- Pair it with `.searchable(...)`; the default toolbar item controls placement, while `.searchable` provides the search state and prompt.
- Use `ToolbarSpacer(placement: .bottomBar)` to separate search from trailing actions.
- Put the creation button in a separate `ToolbarItem(placement: .bottomBar)`.
- Prefer a compose-style symbol such as `square.and.pencil` when the action creates a record or entry.
- Use a plain `plus` only when the object being created is visually or semantically generic.
- Do not recreate this pattern with custom bottom bars, manual safe-area overlays, or custom Liquid Glass capsules.

Example:

```swift
.toolbar {
    DefaultToolbarItem(kind: .search, placement: .bottomBar)
    ToolbarSpacer(placement: .bottomBar)

    ToolbarItem(placement: .bottomBar) {
        Button {
            // Create
        } label: {
            Image(systemName: "square.and.pencil")
        }
    }
}
.searchable(text: $searchText, placement: .toolbar, prompt: "Search")
```

## 2. Feedback And Notifications

Feedback should be quiet, useful, and tied to user intent.

### Background Sync

- Do not show a success toast after background sync completes.
- If sync succeeds, keep the interface stable and let updated content speak for itself.
- If sync fails and cached content exists, keep showing cached content.
- Surface sync failure with a subtle, non-blocking notice only when the failure matters to the current screen.
- Avoid alarming colors for recoverable sync failures.
- Do not interrupt the user with modal alerts for background sync failure.

### User-Initiated Actions

- Do not show celebratory success messages for routine actions.
- For reversible actions that remove content from the current view, show a temporary undo feedback.
- For irreversible destructive actions, require confirmation before executing.
- The feedback should describe what changed and expose the most useful next action.

Examples:

- Archive group: show `Archived` with `Undo`.
- Delete group: confirm first, then remove after confirmation.
- Successful refresh: no message.
- Failed refresh with cached content: show a subtle failure notice.

## 3. Undo Feedback

Undo feedback is used when an action changes the visible list but can be safely reversed.

### Behavior

- Show undo feedback immediately after the action completes locally.
- Keep it temporary and non-blocking.
- Place it near the bottom safe area, above persistent bottom controls if any.
- Include one concise message and one action:
  - message: what happened
  - action: `Undo`
- If the user taps `Undo`, restore the item to its previous position when possible.
- If the timeout expires, keep the action committed.

### Visual Rules

- Use native-feeling compact surfaces.
- Avoid large banners, modal alerts, or heavy cards.
- Keep contrast sufficient in both light and dark mode.
- Do not use strong success colors.

### Copy Rules

- Use short past-tense copy.
- Prefer object-aware text when space allows.

Examples:

- `Archived`
- `May Trip archived`
- `Undo`

## 4. Secondary Panels

A secondary panel is used for related management surfaces that should not replace the primary task context.

### When To Use

- Use a secondary panel for low-frequency management views.
- Use a secondary panel for local detail workspaces that should keep the parent page in context.
- Use it when the user should be able to return naturally to the current page after reviewing or restoring content.
- Do not use it for primary drill-down content, such as a normal group detail page.

### Presentation

- Present as a native sheet or panel.
- Prefer medium-to-large detents when the content is short.
- Allow expansion to a larger detent if the content can scroll.
- Use a visible drag indicator when the panel supports expansion.
- The panel owns its own title and close behavior.
- Keep toolbar actions local to the panel.

### Navigation

- The parent page opens the panel from a page-level action.
- The panel can contain its own list and local row actions.
- Closing the panel returns to the parent page without losing parent scroll position.

## 5. Destructive And Reversible Actions

Use a clear distinction between reversible removal and destructive deletion.

### Archive

- Archive is reversible.
- It can be exposed from row context menus.
- It should remove the item from the current active list.
- It should show undo feedback.
- Archived items remain accessible from an archived-management surface.

### Delete

- Delete is destructive.
- It must be confirmed before execution.
- It should not be placed as the default or easiest action.
- It can appear in context menus using destructive role styling.
- Undo is optional only if the data model can guarantee safe restoration; otherwise confirmation is required.

## 6. Content Overflow

Long content should degrade predictably across the app. Preserve meaning first, then compress format, then limit lines, and only then truncate.

Priority order inside constrained rows:

1. Money value and sign
2. Status color or semantic state
3. Primary title
4. Date, members, and secondary metadata
5. Decorative elements

### Money Values

Money values are core data and must not be truncated with an ellipsis.

- Prefer full values when the container can hold them.
- Use monospaced digits for scannable money values.
- Allow modest font scaling for prominent balance values before switching to compact notation.
- When the value is too long, use locale-aware compact notation.
- Preserve the complete value for accessibility labels and detail views.
- Do not display values like `+¥128...`.

English compact examples:

- `¥1.2K`
- `¥1.2M`
- `¥1.2B`

Chinese compact examples:

- `¥1.2万`
- `¥128万`
- `¥1.2亿`

Rules:

- Keep about three significant digits for compact values.
- Remove unnecessary decimal places in compact values.
- Use `K`, `M`, and `B` in English contexts, not lowercase `k` or `m`.
- Use `万` and `亿` in Chinese contexts.
- For settled or zero balances, use a neutral color and the full zero value when possible: `¥0.00`.

### Text

Text overflow depends on the role of the text.

Page titles and group titles:

- Prefer one line.
- Use tail truncation when needed.
- Do not wrap navigation titles into custom multi-line headers.

List row titles:

- Prefer one line.
- Let the title yield space to money values and disclosure indicators.
- Use tail truncation when needed.

Descriptions, notes, and remarks:

- Lists may show one or two lines depending on row density.
- Detail pages may show more complete text.
- Long user-authored remarks should be readable in detail contexts, not forced into dense list rows.

Rules:

- Lists optimize for scanning.
- Detail pages optimize for completeness.
- Do not invent subtitles or helper copy to balance layout.
- Do not let text overlap adjacent values.

### Avatar Groups

Avatar groups indicate participation and social context. They should be generous enough to feel human, but bounded enough to protect layout.

Display limits:

- Default roomy surfaces: show up to `4` avatars, then `+N`.
- Compact rows: show up to `3` avatars, then `+N`.
- Very narrow spaces: show up to `2` avatars, then `+N`.
- Dedicated member lists or member panels: show the full list.

Examples:

- 4 members on a summary card: `H L M Y`
- 7 members on a summary card: `H L M Y +3`
- 7 members in a compact row: `H L M +4`

Visual rules:

- Render `+N` as an avatar-sized circle, not loose text.
- Keep avatar size and overlap consistent within the same component.
- Do not reserve empty avatar slots for missing members.
- The avatar group is a preview of participation, not the complete member-management UI.

Accessibility rules:

- Decorative initials inside the avatar group may be hidden from VoiceOver.
- The parent row or card should expose a meaningful label, such as `4 members` or `7 members`.
- Full member names belong in the member list or detail panel.
