# Group settings UX specification

## 1. Entry and presentation

Group settings is a low-frequency management surface for one group. It should be reachable without exposing management actions directly on the group detail page.

### Entry

- The group detail top-right `ellipsis` opens `Group settings` directly.
- Do not show a top-level action menu from this `ellipsis`.
- Do not expose `Share`, `Archive group`, or `Delete group` in the group detail top bar.
- Adding expenses remains a separate bottom creation action and does not belong in settings.

### Presentation

- Present as a native sheet from the group detail page.
- Use a local `NavigationStack` inside the sheet.
- Use the large detent by default:
  - `.presentationDetents([.large])`
- Show the drag indicator:
  - `.presentationDragIndicator(.visible)`
- Closing or confirming returns to the group detail page without changing the parent scroll position.

### Top bar

- Title: `Group settings`.
- Use sentence case for all English copy.
- Use native toolbar placements:
  - cancellation action on the left
  - confirmation action on the right
- The cancel action uses `xmark`.
- The confirmation action uses `checkmark`.
- The confirmation action uses the app theme color.
- The sheet root should apply the app theme tint so native controls, insertion cursors, and confirmation actions use the same accent.

## 2. Group section

The Group section contains only information and edits that define the group itself.

### Group name

- Show one editable text field for the group name.
- Label/placeholder: `Name`.
- The insertion cursor should use the app theme tint.
- Use native text field behavior; do not custom draw the cursor, underline, or focus state.
- Do not show created date, metadata, audit information, or currency while those concepts are not supported by the product.

### Group ID

- Show the group's shareable identifier in the Group section.
- Label: `Group ID`.
- The value is read-only.
- Use monospaced text for the value, such as `GRP-MAY-8K2`.
- Allow text selection or copying so a member can send it to someone joining the group.
- Do not make this row visually primary; it is reference information, not an action.
- Do not hide the Group ID inside developer/debug metadata.

### Members summary

- Show `Members` as an informational row inside the Group section.
- Do not push into a member-management page from this row.
- Show member identity with a compact stacked-avatar treatment:
  - visible initials for the first few members
  - `+N` overflow indicator when members exceed the visible count
  - total count text, such as `6 total`
- Keep the row readable for larger groups without showing a long vertical member list.
- Do not support remove member, edit display name, or role management in this surface until backend behavior exists.

## 3. People section

The People section contains only member-addition actions.

Entry points:

- Create group sheet: add initial real members before the group is created.
- People setup empty state: add members when a group has only the current user and no records.
- Group settings sheet: add members to an existing group.

All three entry points use the same product language and flow:

- `Add member` for searching existing users.
- `Add temporary member` for creating a temporary participant by name.

### Add member

- Label: `Add member`.
- Use a native stack-push row with the system chevron on the trailing edge.
- Do not show an icon.
- Use primary text color, not the theme accent, so it does not compete with the confirmation action.
- Push into the shared member-search flow inside the current sheet's `NavigationStack`; do not present a second modal.
- Search existing users by name.
- Allow selecting one or more users from the search results.
- Hide or disable users who are already in the group.
- Confirming adds the selected users to the group.
- In implementation, this may call the existing backend `invite` endpoint, but the product copy should remain `Add member`.

### Add Temporary Member

- Label: `Add temporary member`.
- Use a plain text row with system-native row affordance.
- Do not show an icon.
- Use primary text color, not the theme accent.
- Open a lightweight native dialog or alert for entering the temporary member's name.
- The dialog title is `Add temporary member`.
- The name field uses the sheet theme tint for its cursor.
- The `Add` confirmation action uses the theme tint.
- `Cancel` remains neutral.
- Disable `Add` until the name is non-empty after trimming whitespace.

## 4. Management section

Management actions are lower-frequency and potentially destructive. Keep them grouped together and visually quiet unless destructive.

### Archive

- Label: `Archive group`.
- Place in the Management section.
- Do not show an icon.
- Use primary text color, not the theme accent.
- Ask for confirmation before archiving.
- Archive is reversible at the product level; after execution, active lists should remove the group and show undo feedback according to `common-ux.md`.

### Delete

- Label: `Delete group`.
- Place in the Management section, near `Archive group`.
- Do not show an icon.
- Use native destructive role styling.
- Ask for confirmation before deleting.
- Do not make delete the easiest or most visually prominent action.

## 5. Omitted items

Do not include these items in the current settings surface:

- Share action.
- Currency.
- Created date or metadata.
- Audit information.
- Settlement or accounting rules.
- Member removal.
- Member display name editing.
- Role or permission management.
- A separate members page.

## 6. SwiftUI pattern

```swift
struct GroupSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = "May Trip"
    @State private var isShowingAddTemporaryMember = false
    @State private var tempMemberName = ""

    var body: some View {
        Form {
            Section("Group") {
                TextField("Name", text: $groupName)

                HStack {
                    Text("Group ID")
                    Spacer()
                    Text("GRP-MAY-8K2")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                HStack {
                    Text("Members")
                    Spacer()
                    MemberStack()
                }
            }

            Section("People") {
                NavigationLink {
                    AddMemberView()
                } label: {
                    Text("Add member")
                        .foregroundStyle(.primary)
                }

                Button {
                    isShowingAddTemporaryMember = true
                } label: {
                    Text("Add temporary member")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section("Management") {
                Button {
                    // Confirm archive
                } label: {
                    Text("Archive group")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button("Delete group", role: .destructive) {
                    // Confirm delete
                }
            }
        }
        .navigationTitle("Group settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        }
    }
}
```

## 7. Rejected variants

- Keeping `Share`, `Archive group`, or `Delete group` in the group detail `ellipsis` menu.
- Showing `Add member` or `Add temporary member` in the theme accent color.
- Adding icons to People or Management rows.
- Showing all members as a long noninteractive list.
- Navigating into a members page that cannot support meaningful member actions.
- Showing currency or metadata before the product supports them.
- Exposing settlement/accounting rules in settings.
