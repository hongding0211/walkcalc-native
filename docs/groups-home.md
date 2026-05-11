# Groups Home UX Specification

## 1. Top Layout

The Groups home page uses a native iOS navigation header, following the Notes app folder screen pattern.

### Structure

- Use `NavigationStack` as the page container.
- Use the system title API: `.navigationTitle("Groups")`.
- Use `.navigationBarTitleDisplayMode(.large)`.
- Do not draw a custom title inside the scroll content.
- Do not show a subtitle under the title.
- The first visible content inside the scroll view starts below the system large title.

### Scroll Behavior

- The title must be native and dynamic.
- When the page is at rest near the top, `Groups` appears as the large navigation title.
- When the user scrolls upward, iOS collapses the large title into the small navigation bar title automatically.
- Do not recreate this behavior with manual geometry, opacity, scale, or overlay text unless the native behavior cannot satisfy a future requirement.

### Top-Right Actions

- Show two actions in the top-right navigation bar:
  - Add: `plus`
  - More: `ellipsis`
- Use separate `ToolbarItem(placement: .topBarTrailing)` entries for the two actions.
- Use native `Button` controls with SF Symbols.
- Do not wrap the two actions in `ToolbarItemGroup`, because the system may visually group them into one glass capsule.
- Do not apply custom circular glass styling inside the navigation toolbar.
- Do not show a profile avatar in this page header.

### Interaction Semantics

- `plus` opens a native menu anchored to the toolbar button.
- The add menu contains:
  - `Create group`
  - `Join group`
- `ellipsis` opens `Settings` directly as a full-height native sheet.
- Do not show a top-level action menu from this `ellipsis`.
- Do not place per-group actions such as `Archive` or `Delete` behind the home `ellipsis` action.
- Per-group actions belong to each group row's context menu.
- Both actions must have accessibility labels:
  - `Add group`
  - `Settings`

### Visual Rules

- The navigation bar should inherit the page's warm canvas background.
- Keep toolbar icons visually native and lightweight.
- Do not apply the app theme tint to the page root, because the top-right toolbar icons should remain system primary: black in light mode and white in dark mode.
- Avoid custom shadows, borders, or nested glass effects in the toolbar.
- Page-level Liquid Glass may appear in content cards, but not as an extra wrapper around toolbar buttons.

### Current SwiftUI Pattern

```swift
NavigationStack {
    ZStack {
        SoftLedgerTheme.canvas.ignoresSafeArea()
        ScrollView {
            // Page content starts here.
        }
    }
    .navigationTitle("Groups")
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    // Create group
                } label: {
                    Label("Create group", systemImage: "person.2")
                }

                Button {
                    // Join group
                } label: {
                    Label("Join group", systemImage: "person.2.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add group")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // Open settings
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Settings")
        }
    }
    .toolbarBackground(.hidden, for: .navigationBar)
}
```

### Rejected Variants

- Custom in-content header with `Text("Groups")`.
- Header subtitle such as `Shared costs, settled calmly`.
- Profile/avatar button in the top-right header.
- Custom glass circle buttons inside the system toolbar.
- Grouped toolbar action capsules for `plus` and `ellipsis`.
- Making `plus` immediately create a group when joining an existing group is also a supported primary path.

## 2. Summary Area

The summary area is a lightweight account-status card. It should answer one question quickly: "What is my overall balance across groups?"

### Role

- Treat the card as a status summary, not a dashboard.
- Keep the card calm and sparse.
- Do not use the card for task reminders, alerts, or list metadata.
- The primary visual focus is the total balance amount.

### Content

- Show `Total balance` as the card label.
- Show the net total balance as the dominant value.
- Use monospaced digits for money values.
- Show a quiet scope subtitle such as `Across 4 groups`.
- Do not show `3 groups` in the card; group count belongs in the `All groups` section header.
- Do not show action reminders such as `2 need action` in the card.
- Do not show a directional subtitle such as `I owe` or `Owed to me`.

### Breakdown

- Do not show `Owed to me` or `I owe` in the card.
- Do not reserve space for a breakdown area.
- Keep the card aligned with the group detail balance card, but let Home carry one extra scope line so it reads as a global summary.

### Visual Weight

- The card may use the page's soft material/glass surface.
- Use a subtle border to separate the card from the canvas.
- Use only a very light shadow, if any.
- Avoid heavy web-style elevation.
- Avoid nested card backgrounds inside the summary card.
- Keep spacing generous enough for the total balance to breathe.

### Current SwiftUI Pattern

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("Total balance")
    Text("+¥128.40")
        .monospacedDigit()
    Text("Across 4 groups")
}
```

### Rejected Variants

- Showing `3 groups` in the summary card.
- Showing `2 need action` or similar task pressure in the summary card.
- Rendering `Owed to me` and `I owe` as mini cards.
- Showing `Owed to me` and `I owe` as inline breakdown values.
- Showing zero-value or empty breakdown cells.
- Using the summary card as a dense dashboard.

## 3. Group List

To be specified.

## 4. Empty And Loading States

### Empty State: No Groups

The empty state is the first-run version of the Groups home page. It should feel native, calm, and immediately actionable.

### Structure

- Keep the same native page container as the populated state:
  - `NavigationStack`
  - `.navigationTitle("Groups")`
  - `.navigationBarTitleDisplayMode(.large)`
  - top-right `plus` and `ellipsis` toolbar actions
- Do not show the summary card when there are no groups.
- Do not show the `All groups` section header when there are no groups.
- Do not show an empty list container, placeholder rows, or disabled group cards.
- Place the empty state inside the scroll content, visually above the vertical midpoint.

### Content

- Use a small SF Symbol illustration, currently `person.2`.
- Use the title: `No groups yet`.
- Use one short explanatory sentence:
  - `Create a group or join one shared by friends, roommates, or a trip.`
- Provide two clear actions:
  - `Create group`
  - `Join group`
- The page-level top-right `plus` remains available and opens the same add menu as the populated state.

### Visual Weight

- The empty state should be lightweight, not a dashboard card.
- The icon may sit in a simple circular surface using the page's paper color.
- Keep the text centered inside the empty state block.
- Do not use a large marketing illustration.
- Do not add feature explanations, onboarding steps, or sample content.
- Do not use strong shadows or dense glass containers.

### Interaction Semantics

- Tapping `Create group` starts the new group flow.
- Tapping `Join group` starts the join group flow.
- Tapping the navigation bar `plus` opens the add menu with both choices.
- The `ellipsis` action opens the full-height Settings sheet.
- Empty state content should expose the same creation and joining concepts as the toolbar add menu.

### Current SwiftUI Pattern

```swift
if groups.isEmpty {
    EmptyState()
} else {
    BalanceCard()
    SectionHeader()
    GroupList()
}
```

```swift
VStack(spacing: 18) {
    Image(systemName: "person.2")

    VStack(spacing: 6) {
        Text("No groups yet")
        Text("Create a group or join one shared by friends, roommates, or a trip.")
    }

    HStack(spacing: 10) {
        Button {
            // Create group
        } label: {
            Label("Create group", systemImage: "plus")
        }

        Button {
            // Join group
        } label: {
            Label("Join group", systemImage: "person.2.badge.plus")
        }
    }
}
```

### Rejected Variants

- Showing `Total balance` with `¥0.00`.
- Showing `All groups` with an empty count.
- Showing fake sample groups.
- Showing a large tutorial card.
- Hiding `Join group` only in the top-right add menu.
- Showing more than the two relevant actions: create and join.
- Filling the empty page with explanatory copy.

### Loading State

Loading should feel like a temporary system state, not a new visual module.

### First Load With No Cache

- Keep the native page container:
  - `NavigationStack`
  - `.navigationTitle("Groups")`
  - `.navigationBarTitleDisplayMode(.large)`
  - top-right toolbar actions
- Do not render summary-card skeletons.
- Do not render fake group rows.
- Do not show the empty state until loading has finished and the result is confirmed empty.
- Show a lightweight centered loading block inside the scroll content:
  - `ProgressView()`
  - optional text: `Loading groups...`
- Keep the block visually quieter than the empty state.
- Do not use an icon circle, illustration, large card, or heavy glass container.

### Refresh With Existing Cache

- Keep showing the cached summary and group list.
- Do not replace the page with a loading screen.
- Do not remove existing groups while refresh is in progress.
- Use a native refresh indicator or subtle progress affordance if needed.
- The user should still be able to read and navigate the existing groups while refresh runs.

### Load Failure

- Do not treat load failure as the empty state.
- If cached data exists, keep showing it and surface the failure unobtrusively.
- If no cached data exists, show a compact error state:
  - title: `Couldn’t load groups`
  - action: `Try again`
- Keep the error state visually closer to loading than to onboarding.
- Avoid alarming colors unless the failure blocks all use.

### Current SwiftUI Pattern

```swift
switch state {
case .loading where groups.isEmpty:
    LoadingState()
case .loaded where groups.isEmpty:
    EmptyState()
case .failed where groups.isEmpty:
    ErrorState()
default:
    BalanceCard()
    SectionHeader()
    GroupList()
}
```

```swift
VStack(spacing: 10) {
    ProgressView()
    Text("Loading groups...")
        .font(.callout)
        .foregroundStyle(.secondary)
}
```

### Rejected Variants

- Skeleton cards for the summary area.
- Skeleton rows for groups.
- Replacing cached content with a full-page loading state during refresh.
- Showing empty state before loading has completed.
- Using a large branded loading illustration.

## 5. Actions And Navigation

Groups home follows the shared rules in `docs/common-ux.md` for feedback, undo, secondary panels, and destructive actions.

### Add Group Menu

The top-right `plus` is an add menu, not a single create action.

Menu items:

- `Create group`
- `Join group`

Rules:

- Use a native `Menu` anchored to the `plus` toolbar button.
- Keep the menu short; do not add archive, settings, or per-group actions here.
- `Create group` starts the group creation sheet.
- `Join group` opens a lightweight Group ID dialog.
- The empty state should expose both actions directly, while the toolbar keeps them inside the add menu.

### Join Group Flow

Joining an existing group should be lightweight because the user only needs an identifier from another member.

- Present a native alert/dialog from `Join group`.
- Title: `Join group`.
- Field label/placeholder: `Group ID`.
- Use the app theme tint for the insertion cursor and confirm action.
- `Cancel` is neutral.
- `Join` is disabled until the trimmed Group ID is non-empty.
- Do not ask for group name, members, currency, or other setup fields in this flow.
- If joining fails, show a subtle failure notice according to `common-ux.md`.

### Create Group Flow

Creating a group needs a little more setup, so it should use a native sheet instead of an alert.

- Present as a native sheet from `Create group`.
- Use a local `NavigationStack`.
- Use the large detent by default:
  - `.presentationDetents([.large])`
- Show the drag indicator:
  - `.presentationDragIndicator(.visible)`
- Title: `Create group`.
- Use cancellation action `xmark` on the left.
- Use confirmation action `checkmark` on the right.
- Disable confirmation until the group name is non-empty after trimming whitespace.
- Apply the app theme tint to the sheet root so input cursors and confirmation actions match the theme.

Fields:

- `Name`
- `Members`

Initial members:

- Default to the current user.
- Show members using the same stacked-avatar summary pattern as `Group settings`.
- Provide `Add member`.
- Provide `Add temporary member`.
- Do not require the user to choose an icon, subtitle, currency, accounting rule, or metadata.

Member-add behavior:

- `Add member` should share the same product behavior and copy as `Group settings`.
- `Add member` pushes into the shared member-search flow inside the current create-group sheet stack, with a native trailing chevron.
- `Add temporary member` opens the same lightweight name-entry dialog used in `Group settings`.

### Page-Level Settings Sheet

The top-right `ellipsis` opens `Settings` directly. This is an account-level management surface, so it should default to a full-height native sheet instead of a medium detent.

Presentation:

- Use a local `NavigationStack`.
- Use the large detent by default:
  - `.presentationDetents([.large])`
- Show the drag indicator:
  - `.presentationDragIndicator(.visible)`
- Title: `Settings`.
- Use cancellation action `xmark` on the left.
- Use confirmation action `checkmark` on the right.

Content:

- Account section:
  - show the current signed-in user with avatar and name.
  - include `Edit profile`.
- Groups section:
  - include `Archived groups` as a `NavigationLink`.
- Final standalone section:
  - include `Log out` as a destructive action.

Rules:

- `Edit profile` opens the external SSO profile page in production.
- In the playground, `Edit profile` may show a placeholder notice instead of opening SSO.
- `Archived groups` pushes inside the Settings sheet's navigation stack.
- Do not give `Log out` a section title such as `Session`; the destructive action should stand alone.
- Do not include per-group actions in Settings except archived-group management inside `Archived groups`.

### Archived groups entry

- `Archived groups` is reached from `Settings`.
- It pushes a secondary view inside the Settings sheet's `NavigationStack`.
- The panel is for low-frequency archive management, not for normal group browsing.
- The panel owns its own title: `Archived groups`.
- The panel should include archived group rows and local actions for restoring or deleting archived groups.
- Going back returns to `Settings`; closing Settings returns to the Groups home page.

### Row Context Menu

Each group row supports a long-press context menu.

Menu items:

- `Archive`
- `Delete`

Rules:

- `Archive` is reversible.
- `Delete` is destructive.
- Do not expose archive/delete through swipe actions on the home list.
- Do not show archive/delete in the home `ellipsis` action.

### Archive Flow

- User long-presses a group row.
- User chooses `Archive`.
- The group is removed from the active `All groups` list.
- Show temporary undo feedback:
  - message: `Archived` or `{Group Name} archived`
  - action: `Undo`
- If the user taps `Undo`, restore the group to its previous list position when possible.
- If the undo feedback expires, keep the group archived.
- The archived group remains available from `ellipsis` -> `Settings` -> `Archived groups`.

### Delete Flow

- User long-presses a group row.
- User chooses `Delete`.
- Show a confirmation before deleting.
- Use destructive styling for the delete confirmation action.
- After confirmation, remove the group.
- Do not show delete as a swipe action.

### Sync Feedback

- Successful background sync shows no message.
- Failed background sync uses subtle, non-blocking feedback.
- If cached groups exist, keep showing the cached list when sync fails.
- Do not replace cached content with an error screen.
