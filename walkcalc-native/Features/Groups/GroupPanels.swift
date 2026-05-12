import SwiftUI
import UIKit

struct GroupSheetView: View {
    @EnvironmentObject private var store: WalkcalcStore
    let groupId: String
    let sheet: GroupSheet
    @Binding var activeSheet: GroupSheet?
    let dismissGroup: () -> Void

    private var group: WalkGroup? {
        store.group(id: groupId)
    }

    var body: some View {
        switch sheet {
        case .newExpense:
            NavigationStack {
                RecordEditorView(groupId: groupId) {
                    activeSheet = nil
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)

        case .editExpense(let record):
            NavigationStack {
                RecordEditorView(groupId: groupId, record: record) {
                    activeSheet = nil
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)

        case .groupSettings:
            if let group {
                NavigationStack {
                    GroupSettingsSheet(group: group, onDone: {
                        activeSheet = nil
                    }, onArchive: {
                        activeSheet = nil
                        dismissGroup()
                    }, onDelete: {
                        activeSheet = nil
                        dismissGroup()
                    })
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }

        case .balances(let member):
            if let group {
                BalancesWorkspace(group: group, initialMember: member)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }

        case .peopleSetup:
            if let group {
                NavigationStack {
                    PeopleSetupSheet(group: group) {
                        activeSheet = nil
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

struct CreateGroupSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let onDone: () -> Void
    @State private var groupName = ""
    @State private var selectedUsers: [UserProfile] = []
    @State private var tempUsers: [String] = []

    private var members: [Member] {
        var result: [Member] = []
        if let user = store.user {
            result.append(Member(uuid: user.uuid, name: user.name, avatar: user.avatar, debtMinor: "0", costMinor: "0"))
        }
        result.append(contentsOf: selectedUsers.map { Member(uuid: $0.uuid, name: $0.name, avatar: $0.avatar, debtMinor: "0", costMinor: "0") })
        result.append(contentsOf: tempUsers.map { Member(uuid: $0, name: $0, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true) })
        return result
    }

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section(L("Group")) {
                TextField(L("Name"), text: $groupName)
                    .textInputAutocapitalization(.words)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Initial members")) {
                NavigationLink {
                    InitialMembersView(currentUser: store.user, selectedUsers: $selectedUsers, tempUsers: $tempUsers)
                } label: {
                    HStack {
                        Text(L("Members"))
                        Spacer()
                        SoftLedgerAvatarStack(members: members, visibleCount: 4, borderColor: SoftLedgerTheme.formPaper, showsTotal: true)
                    }
                }

                NavigationLink {
                    AddMemberSearchView(existingMemberIds: Set(members.map(\.uuid))) { users in
                        for user in users where !selectedUsers.contains(user) {
                            selectedUsers.append(user)
                        }
                    }
                } label: {
                    Text(L("Add member"))
                        .foregroundStyle(.primary)
                }

                NavigationLink {
                    AddTemporaryMemberView(existingNames: Set(tempUsers)) { names in
                        for name in names where !tempUsers.contains(name) {
                            tempUsers.append(name)
                        }
                    }
                } label: {
                    Text(L("Add temporary member"))
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Create group"))
        .navigationBarTitleDisplayMode(.inline)
        .softLedgerDismissesKeyboardOnBackgroundTap()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(L("Cancel"))
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if await store.createGroup(name: name, users: selectedUsers, tempUsers: tempUsers) {
                            dismiss()
                            onDone()
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(SoftLedgerTheme.accent)
                .disabled(!canCreate)
                .accessibilityLabel(L("Create"))
            }
        }
    }
}

private struct InitialMembersView: View {
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 30

    let currentUser: UserProfile?
    @Binding var selectedUsers: [UserProfile]
    @Binding var tempUsers: [String]

    private var currentMember: Member? {
        currentUser.map { Member(uuid: $0.uuid, name: $0.name, avatar: $0.avatar, debtMinor: "0", costMinor: "0") }
    }

    var body: some View {
        Form {
            Section(L("Members")) {
                if let currentMember {
                    InitialMemberRow(member: currentMember)
                }

                ForEach(selectedUsers) { user in
                    InitialMemberRow(
                        member: Member(uuid: user.uuid, name: user.name, avatar: user.avatar, debtMinor: "0", costMinor: "0"),
                        onDelete: { remove(user) }
                    )
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Temporary members")) {
                if tempUsers.isEmpty {
                    Text(L("No temporary members"))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .frame(minHeight: avatarSize, alignment: .leading)
                } else {
                    ForEach(tempUsers, id: \.self) { name in
                        InitialMemberRow(
                            member: Member(uuid: name, name: name, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true),
                            onDelete: { removeTemporaryMember(named: name) }
                        )
                    }
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .navigationTitle(L("Members"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func remove(_ user: UserProfile) {
        selectedUsers.removeAll { $0.uuid == user.uuid }
    }

    private func removeTemporaryMember(named name: String) {
        tempUsers.removeAll { $0 == name }
    }
}

private struct InitialMemberRow: View {
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 30
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12

    let member: Member
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: rowSpacing) {
            SoftLedgerAvatar(member: member, size: avatarSize)

            Text(member.name)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 0)

            if let onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("Remove %@").replacingOccurrences(of: "%@", with: member.name))
            }
        }
        .frame(minHeight: avatarSize, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct AddTemporaryMemberView: View {
    @Environment(\.dismiss) private var dismiss

    let existingNames: Set<String>
    let onAdd: ([String]) -> Void
    @State private var name = ""
    @State private var selectedNames: [String] = []

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddCandidate: Bool {
        let key = nameKey(trimmedName)
        return !key.isEmpty && !existingNameKeys.contains(key) && !selectedNameKeys.contains(key)
    }

    private var canAdd: Bool {
        !selectedNames.isEmpty
    }

    private var existingNameKeys: Set<String> {
        Set(existingNames.map { nameKey($0) })
    }

    private var selectedNameKeys: Set<String> {
        Set(selectedNames.map { nameKey($0) })
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    TextField(L("Name"), text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addCandidate)

                    if canAddCandidate {
                        Button {
                            addCandidate()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.accent)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("Add"))
                    }
                }
            } footer: {
                Text(L("Temporary members can participate in expenses without an account."))
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            if !selectedNames.isEmpty {
                Section(L("Selected")) {
                    ForEach(selectedNames, id: \.self) { name in
                        InitialMemberRow(
                            member: Member(uuid: name, name: name, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true),
                            onDelete: { remove(name) }
                        )
                    }
                }
                .listRowBackground(SoftLedgerTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Add temporary member"))
        .navigationBarTitleDisplayMode(.inline)
        .softLedgerDismissesKeyboardOnBackgroundTap()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    submit()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(SoftLedgerTheme.accent)
                .disabled(!canAdd)
                .accessibilityLabel(L("Add"))
            }
        }
    }

    private func addCandidate() {
        guard canAddCandidate else { return }
        selectedNames.append(trimmedName)
        name = ""
    }

    private func remove(_ value: String) {
        selectedNames.removeAll { nameKey($0) == nameKey(value) }
    }

    private func submit() {
        guard canAdd else { return }
        onAdd(selectedNames)
        dismiss()
    }

    private func nameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var accountAvatarSize = 32
    @ScaledMetric(relativeTo: .body) private var accountRowSpacing = 12

    let archivedGroups: [WalkGroup]
    let onDone: () -> Void
    @State private var confirmLogout = false
    @State private var showingProfile = false

    var body: some View {
        Form {
            Section(L("Account")) {
                HStack(spacing: accountRowSpacing) {
                    SoftLedgerAvatar(user: store.user, size: accountAvatarSize)
                    Text(store.user?.name ?? "")
                        .font(.body)
                        .foregroundStyle(SoftLedgerTheme.ink)
                    Spacer()
                }

                Button {
                    showingProfile = true
                } label: {
                    Text(L("Edit profile"))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Groups")) {
                NavigationLink {
                    ArchivedGroupsView(groups: archivedGroups)
                } label: {
                    Text(L("Archived groups"))
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section {
                Button(L("Log out"), role: .destructive) {
                    confirmLogout = true
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(L("Cancel"))
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                    onDone()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(SoftLedgerTheme.accent)
                .accessibilityLabel(L("Done"))
            }
        }
        .alert(L("Confirm logout?"), isPresented: $confirmLogout) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Confirm"), role: .destructive) {
                store.logout()
                dismiss()
                onDone()
            }
        }
        .sheet(isPresented: $showingProfile) {
            SSOProfileView(url: store.api.profileURL(), token: store.token)
                .immersiveWebSheet()
        }
    }
}

struct ArchivedGroupsView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .body) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .caption) private var textSpacing = 4
    @ScaledMetric(relativeTo: .body) private var restoreHorizontalPadding = 6
    @ScaledMetric(relativeTo: .body) private var restoreMinHeight = 44

    let groups: [WalkGroup]
    @State private var deleteCandidate: WalkGroup?

    var body: some View {
        Form {
            Section {
                if groups.isEmpty {
                    Text(L("No archived groups"))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                } else {
                    ForEach(groups) { group in
                        HStack(spacing: rowSpacing) {
                            VStack(alignment: .leading, spacing: textSpacing) {
                                Text(group.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SoftLedgerTheme.ink)
                                    .lineLimit(1)
                                Text(TemporalDisplay.string(fromMilliseconds: group.modifiedAt, context: .compact))
                                    .font(.subheadline)
                                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                Task { _ = await store.unarchiveGroup(group.id) }
                            } label: {
                                Text(L("Restore"))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SoftLedgerTheme.accent)
                                    .padding(.horizontal, restoreHorizontalPadding)
                                    .frame(minHeight: restoreMinHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button(L("Restore")) {
                                Task { _ = await store.unarchiveGroup(group.id) }
                            }
                            Button(L("Delete"), role: .destructive) {
                                deleteCandidate = group
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(L("Delete"), role: .destructive) {
                                deleteCandidate = group
                            }

                            Button(L("Restore")) {
                                Task { _ = await store.unarchiveGroup(group.id) }
                            }
                            .tint(SoftLedgerTheme.accent)
                        }
                    }
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .navigationTitle(L("Archived groups"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("Delete group?"), isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete group"), role: .destructive) {
                if let group = deleteCandidate {
                    Task { _ = await store.deleteGroup(group.id) }
                }
                deleteCandidate = nil
            }
        } message: {
            if deleteCandidate?.shouldShowDeleteResolutionNotice == true {
                Text(L("Any unresolved balances will be automatically resolved to zero before this group is deleted."))
            }
        }
    }
}

struct GroupSettingsSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let group: WalkGroup
    let onDone: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var confirmation: GroupSettingsConfirmation?
    @State private var isShowingArchiveBlockedAlert = false

    init(group: WalkGroup, onDone: @escaping () -> Void, onArchive: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.group = group
        self.onDone = onDone
        self.onArchive = onArchive
        self.onDelete = onDelete
        _name = State(initialValue: group.name)
    }

    private var currentGroup: WalkGroup {
        store.group(id: group.id) ?? group
    }

    var body: some View {
        Form {
            Section(L("Group")) {
                HStack {
                    Text(L("Group name"))

                    Spacer()

                    TextField(L("Group name"), text: $name)
                        .textInputAutocapitalization(.words)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text(L("Group ID"))
                    Spacer()
                    Text(group.id)
                        .font(.body.monospaced())
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .textSelection(.enabled)
                }

                NavigationLink {
                    GroupMembersView(group: currentGroup)
                } label: {
                    HStack {
                        Text(L("Members"))
                        Spacer()
                        SoftLedgerAvatarStack(members: currentGroup.allMembers, visibleCount: 4, borderColor: SoftLedgerTheme.formPaper, showsTotal: false)
                    }
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Members")) {
                NavigationLink {
                    AddMemberSearchView(existingMemberIds: Set(currentGroup.allMembers.map(\.uuid))) { users in
                        Task {
                            _ = await store.addMembers(groupId: group.id, users: users, tempUsers: [])
                        }
                    }
                } label: {
                    Text(L("Add member"))
                        .foregroundStyle(.primary)
                }

                NavigationLink {
                    AddTemporaryMemberView(existingNames: Set(currentGroup.tempUsers.map(\.name))) { values in
                        Task { _ = await store.addMembers(groupId: group.id, users: [], tempUsers: values) }
                    }
                } label: {
                    Text(L("Add temporary member"))
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Management")) {
                Button {
                    if currentGroup.shouldBlockArchive {
                        isShowingArchiveBlockedAlert = true
                    } else {
                        confirmation = .archive
                    }
                } label: {
                    Text(L("Archive group"))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(L("Delete group"), role: .destructive) {
                    confirmation = .delete
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Group settings"))
        .navigationBarTitleDisplayMode(.inline)
        .softLedgerDismissesKeyboardOnBackgroundTap()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(L("Cancel"))
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, trimmed != group.name {
                            _ = await store.changeGroupName(group.id, name: trimmed)
                        }
                        dismiss()
                        onDone()
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(SoftLedgerTheme.accent)
                .accessibilityLabel(L("Done"))
            }
        }
        .alert(confirmationTitle, isPresented: confirmationBinding) {
            switch confirmation {
            case .archive:
                Button(L("Archive group")) {
                    confirmation = nil
                    Task {
                        if await store.archiveGroup(group.id) {
                            dismiss()
                            onArchive()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
            case .delete:
                Button(L("Delete group"), role: .destructive) {
                    confirmation = nil
                    Task {
                        if await store.deleteGroup(group.id) {
                            dismiss()
                            onDelete()
                        }
                    }
                }
            case nil:
                EmptyView()
            }
            Button(L("Cancel"), role: .cancel) { confirmation = nil }
        } message: {
            switch confirmation {
            case .archive:
                Text(L("Only groups with zero balances can be archived."))
            case .delete where currentGroup.shouldShowDeleteResolutionNotice:
                Text(L("Any unresolved balances will be automatically resolved to zero before this group is deleted."))
            default:
                EmptyView()
            }
        }
        .alert(L("Cannot archive group"), isPresented: $isShowingArchiveBlockedAlert) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L("Settle all balances before archiving this group."))
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .archive: L("Archive group?")
        case .delete: L("Delete group?")
        case nil: ""
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )
    }
}

enum GroupSettingsConfirmation: Identifiable {
    case archive
    case delete

    var id: String {
        switch self {
        case .archive: "archive"
        case .delete: "delete"
        }
    }
}

private struct GroupMembersView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalInset = 12
    @ScaledMetric(relativeTo: .caption) private var rowVerticalInset = 6

    let group: WalkGroup

    private var currentGroup: WalkGroup {
        store.group(id: group.id) ?? group
    }

    var body: some View {
        Form {
            Section(L("Members")) {
                ForEach(currentGroup.membersInfo) { member in
                    GroupMemberInfoRow(member: member)
                }
            }
            .listRowInsets(rowInsets)
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Temporary members")) {
                if currentGroup.tempUsers.isEmpty {
                    Text(L("No temporary members"))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                } else {
                    ForEach(currentGroup.tempUsers) { member in
                        GroupMemberInfoRow(member: member)
                    }
                }
            }
            .listRowInsets(rowInsets)
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .navigationTitle(L("Members"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: rowVerticalInset, leading: rowHorizontalInset, bottom: rowVerticalInset, trailing: rowHorizontalInset)
    }
}

private struct GroupMemberInfoRow: View {
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 28
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 36
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 10

    let member: Member

    var body: some View {
        HStack(spacing: rowSpacing) {
            SoftLedgerAvatar(member: member, size: avatarSize, borderColor: SoftLedgerTheme.formPaper)

            Text(member.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .frame(minHeight: rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

struct PeopleSetupSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let group: WalkGroup
    let onDone: () -> Void

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AddMemberSearchView(existingMemberIds: Set(group.allMembers.map(\.uuid))) { users in
                        Task {
                            if await store.addMembers(groupId: group.id, users: users, tempUsers: []) {
                                dismiss()
                                onDone()
                            }
                        }
                    }
                } label: {
                    Text(L("Add member"))
                        .foregroundStyle(.primary)
                }

                NavigationLink {
                    AddTemporaryMemberView(existingNames: Set(group.tempUsers.map(\.name))) { values in
                        Task {
                            if await store.addMembers(groupId: group.id, users: [], tempUsers: values) {
                                dismiss()
                                onDone()
                            }
                        }
                    }
                } label: {
                    Text(L("Add temporary member"))
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Add people"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

struct AddMemberSearchView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 30
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12

    let existingMemberIds: Set<String>
    let onAdd: ([UserProfile]) -> Void

    @State private var searchText = ""
    @State private var results: [UserProfile] = []
    @State private var selectedUsers: [UserProfile] = []
    @State private var isSearching = false
    @State private var completedSearchText = ""

    private var canAdd: Bool {
        !selectedUsers.isEmpty
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLoadingSearch: Bool {
        !trimmedSearchText.isEmpty && (isSearching || completedSearchText != trimmedSearchText)
    }

    private var matchingResults: [UserProfile] {
        guard completedSearchText == trimmedSearchText else { return [] }
        return results.filter { !existingMemberIds.contains($0.uuid) }
    }

    private var visibleResults: [UserProfile] {
        matchingResults.filter { !selectedUserIds.contains($0.uuid) }
    }

    private var showsNoResults: Bool {
        !trimmedSearchText.isEmpty && !isLoadingSearch && matchingResults.isEmpty
    }

    private var showsAllMatchesSelected: Bool {
        !trimmedSearchText.isEmpty && !isLoadingSearch && !matchingResults.isEmpty && visibleResults.isEmpty
    }

    private var showsResultsSection: Bool {
        !trimmedSearchText.isEmpty
    }

    private var selectedUserIds: Set<String> {
        Set(selectedUsers.map(\.uuid))
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Search by name"), text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            if showsResultsSection {
                Section(L("Results")) {
                    if isLoadingSearch {
                        searchStatusRow(isLoading: true, text: L("Searching members..."))
                    } else if showsNoResults {
                        searchStatusRow(isLoading: false, text: L("No matching members"))
                    } else if showsAllMatchesSelected {
                        searchStatusRow(isLoading: false, text: L("All matching members selected"))
                    }
                    ForEach(visibleResults) { user in
                        Button {
                            add(user)
                        } label: {
                            memberRow(user: user, trailingSystemImage: "plus.circle.fill")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(SoftLedgerTheme.formPaper)
            }

            if !selectedUsers.isEmpty {
                Section(L("Selected")) {
                    ForEach(selectedUsers) { user in
                        HStack(spacing: rowSpacing) {
                            SoftLedgerAvatar(user: user, size: avatarSize)
                            Text(user.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                remove(user)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SoftLedgerTheme.secondaryInk.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L("Remove %@").replacingOccurrences(of: "%@", with: user.name))
                        }
                        .frame(minHeight: avatarSize, alignment: .leading)
                    }
                }
                .listRowBackground(SoftLedgerTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Add member"))
        .navigationBarTitleDisplayMode(.inline)
        .softLedgerDismissesKeyboardOnBackgroundTap()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onAdd(selectedUsers)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(SoftLedgerTheme.accent)
                .disabled(!canAdd)
                .accessibilityLabel(L("Add"))
            }
        }
        .task(id: searchText) {
            let query = trimmedSearchText
            guard !query.isEmpty else {
                results = []
                completedSearchText = ""
                isSearching = false
                return
            }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let searchResults = await store.searchUsers(name: query)
            guard !Task.isCancelled else { return }
            results = searchResults
            completedSearchText = query
            isSearching = false
        }
    }

    private func searchStatusRow(isLoading: Bool, text: String) -> some View {
        HStack(spacing: rowSpacing) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(SoftLedgerTheme.secondaryInk)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(SoftLedgerTheme.secondaryInk)

            Spacer(minLength: 0)
        }
        .frame(minHeight: avatarSize, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func memberRow(user: UserProfile, trailingSystemImage: String) -> some View {
        HStack(spacing: rowSpacing) {
            SoftLedgerAvatar(user: user, size: avatarSize)
            Text(user.name)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: trailingSystemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.accent)
        }
        .frame(minHeight: avatarSize, alignment: .leading)
    }

    private func add(_ user: UserProfile) {
        if !selectedUsers.contains(user) {
            selectedUsers.append(user)
        }
    }

    private func remove(_ user: UserProfile) {
        selectedUsers.removeAll { $0.uuid == user.uuid }
    }
}

struct RecordEditorView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: ExpenseEditorField?

    let groupId: String
    let record: WalkRecord?
    let onDone: () -> Void

    @State private var amount: String
    @State private var paidBy: String
    @State private var splitMembers: Set<String>
    @State private var categoryId: String
    @State private var date = Date()
    @State private var note: String
    @State private var message: String?
    @State private var deleteCandidate: WalkRecord?
    @State private var hasEditIntent: Bool

    init(groupId: String, record: WalkRecord? = nil, onDone: @escaping () -> Void) {
        self.groupId = groupId
        self.record = record
        self.onDone = onDone
        _amount = State(initialValue: record.map { Money.editableDisplay($0.paidMinor) } ?? "")
        _paidBy = State(initialValue: record?.who ?? "")
        _splitMembers = State(initialValue: Set(record?.forWhom ?? []))
        _categoryId = State(initialValue: record.map { expenseCategory(for: $0).id } ?? "food")
        _note = State(initialValue: record?.text ?? "")
        _date = State(initialValue: record?.occurredAt.walkDate ?? Date())
        _hasEditIntent = State(initialValue: record == nil)
    }

    private var group: WalkGroup? {
        store.group(id: groupId)
    }

    private var members: [Member] {
        group?.allMembers ?? []
    }

    private var title: String {
        guard let record else { return L("New expense") }
        return recordTitle(record)
    }

    private var canSave: Bool {
        (try? Money.parseDisplay(amount)).map { Money.isPositive($0) } == true
            && !paidBy.isEmpty
            && !splitMembers.isEmpty
    }

    private var showsEditActions: Bool {
        record == nil || hasEditIntent
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("¥")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(SoftLedgerTheme.ink)
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .minimumScaleFactor(0.72)
                        .focused($focusedField, equals: .amount)
                }
                .padding(.vertical, 10)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section {
                PaidByInlineEditor(members: members, selection: $paidBy, onEdit: beginEditing)

                SplitInlineEditor(members: members, selection: $splitMembers, onEdit: beginEditing)
                CategoryInlineEditor(selection: $categoryId, onEdit: beginEditing)

                DatePicker(L("Date"), selection: $date)
                    .datePickerStyle(.compact)
                    .simultaneousGesture(TapGesture().onEnded { beginEditing() })
                    .onChange(of: date) { _, _ in beginEditing() }

                TextField(L("Optional note"), text: $note, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .focused($focusedField, equals: .note)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(SoftLedgerTheme.negative)
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            if record != nil {
                Section {
                    Button(L("Delete expense"), role: .destructive) {
                        deleteCandidate = record
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(SoftLedgerTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsEditActions {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        cancelEditing()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L("Cancel"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SoftLedgerTheme.accent)
                    .disabled(!canSave)
                    .accessibilityLabel(L("Save"))
                }
            }
        }
        .task {
            if paidBy.isEmpty {
                paidBy = store.user?.uuid ?? members.first?.uuid ?? ""
            }
            if record == nil {
                focusedField = .amount
            }
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue != nil {
                beginEditing()
            }
        }
        .softLedgerDismissesKeyboardOnBackgroundTap(isActive: focusedField != nil) {
            focusedField = nil
        }
        .recordDeleteConfirmation(groupId: groupId, record: $deleteCandidate) { _ in
            dismiss()
            onDone()
        }
    }

    private func beginEditing() {
        guard record != nil else { return }
        hasEditIntent = true
    }

    private func cancelEditing() {
        guard record != nil else {
            dismiss()
            onDone()
            return
        }
        resetDraft()
        message = nil
        focusedField = nil
        hasEditIntent = false
        dismiss()
        onDone()
    }

    private func resetDraft() {
        amount = record.map { Money.editableDisplay($0.paidMinor) } ?? ""
        paidBy = record?.who ?? store.user?.uuid ?? members.first?.uuid ?? ""
        splitMembers = Set(record?.forWhom ?? [])
        categoryId = record.map { expenseCategory(for: $0).id } ?? "food"
        date = record?.occurredAt.walkDate ?? Date()
        note = record?.text ?? ""
    }

    private func submit() async {
        do {
            _ = try Money.parseDisplay(amount)
        } catch {
            message = L("Enter a valid amount with up to 2 decimal places")
            return
        }
        guard !splitMembers.isEmpty else {
            message = L("Select at least one people.")
            return
        }

        let success: Bool
        if let record {
            success = await store.editRecord(
                groupId: groupId,
                recordId: record.recordId,
                who: paidBy,
                paid: amount,
                forWhom: Array(splitMembers),
                type: categoryId,
                text: note,
                occurredAt: date.timeIntervalSince1970 * 1000,
                isSettlement: record.isDebtResolve
            )
        } else {
            success = await store.addRecord(
                groupId: groupId,
                who: paidBy,
                paid: amount,
                forWhom: Array(splitMembers),
                type: categoryId,
                text: note,
                occurredAt: date.timeIntervalSince1970 * 1000
            )
        }

        if success {
            dismiss()
            onDone()
        } else {
            message = record == nil ? L("Add fail") : L("Edit fail")
        }
    }
}

private struct PaidByInlineEditor: View {
    @ScaledMetric(relativeTo: .caption) private var sectionSpacing = 10
    @ScaledMetric(relativeTo: .caption2) private var itemWidth = 56
    @ScaledMetric(relativeTo: .caption2) private var rowSpacing = 10
    @ScaledMetric(relativeTo: .caption2) private var estimatedItemHeight = 58
    @ScaledMetric(relativeTo: .caption2) private var textSpacing = 5
    @ScaledMetric(relativeTo: .caption2) private var avatarSize = 36
    @ScaledMetric(relativeTo: .caption2) private var verticalPadding = 4

    let members: [Member]
    @Binding var selection: String
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text(L("Paid by"))
                .foregroundStyle(SoftLedgerTheme.ink)

            JustifiedGrid(items: members, id: \.id, itemWidth: itemWidth, rowSpacing: rowSpacing, estimatedItemHeight: estimatedItemHeight) { member in
                Button {
                    onEdit()
                    selection = member.uuid
                } label: {
                    VStack(spacing: textSpacing) {
                        SelectableSplitAvatar(member: member, isSelected: selection == member.uuid, avatarSize: avatarSize)

                        Text(member.name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SoftLedgerTheme.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: itemWidth)
                    }
                    .frame(width: itemWidth)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(L("Paid by")) \(member.name)")
                .accessibilityAddTraits(selection == member.uuid ? .isSelected : [])
            }
        }
        .padding(.vertical, verticalPadding)
    }
}

private enum ExpenseEditorField {
    case amount
    case note
}

private struct SplitInlineEditor: View {
    @ScaledMetric(relativeTo: .caption) private var sectionSpacing = 10
    @ScaledMetric(relativeTo: .caption2) private var itemWidth = 56
    @ScaledMetric(relativeTo: .caption2) private var rowSpacing = 10
    @ScaledMetric(relativeTo: .caption2) private var estimatedItemHeight = 58
    @ScaledMetric(relativeTo: .caption2) private var textSpacing = 5
    @ScaledMetric(relativeTo: .caption2) private var avatarSize = 36
    @ScaledMetric(relativeTo: .caption2) private var verticalPadding = 4

    let members: [Member]
    @Binding var selection: Set<String>
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            HStack {
                Text(L("Split"))
                Spacer()
                Button(L("All")) {
                    onEdit()
                    if selection.count == members.count {
                        selection.removeAll()
                    } else {
                        selection = Set(members.map(\.uuid))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            JustifiedGrid(items: members, id: \.id, itemWidth: itemWidth, rowSpacing: rowSpacing, estimatedItemHeight: estimatedItemHeight) { member in
                Button {
                    onEdit()
                    toggle(member)
                } label: {
                    VStack(spacing: textSpacing) {
                        SelectableSplitAvatar(member: member, isSelected: selection.contains(member.uuid), avatarSize: avatarSize)

                        Text(member.name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SoftLedgerTheme.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: itemWidth)
                    }
                    .frame(width: itemWidth)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, verticalPadding)
    }

    private func toggle(_ member: Member) {
        if selection.contains(member.uuid) {
            selection.remove(member.uuid)
        } else {
            selection.insert(member.uuid)
        }
    }
}

private struct SelectableSplitAvatar: View {
    let member: Member
    let isSelected: Bool
    let avatarSize: CGFloat

    private var frameSize: CGFloat {
        avatarSize + max(2, avatarSize / 18)
    }

    private var checkSize: CGFloat {
        max(12, avatarSize * 0.42)
    }

    private var checkFontSize: CGFloat {
        max(7, checkSize * 0.52)
    }

    private var checkOffset: CGFloat {
        max(1.5, avatarSize / 18)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SoftLedgerAvatar(member: member, size: avatarSize)
                .overlay {
                    Circle()
                        .stroke(isSelected ? SoftLedgerTheme.accent : SoftLedgerTheme.rule.opacity(0.45), lineWidth: isSelected ? max(1.5, avatarSize / 18) : 1)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .fill(SoftLedgerTheme.accent.opacity(0.16))
                    }
                }

            if isSelected {
                Circle()
                    .fill(SoftLedgerTheme.accent)
                    .frame(width: checkSize, height: checkSize)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: checkFontSize, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    .offset(x: checkOffset, y: checkOffset)
            }
        }
        .frame(width: frameSize, height: frameSize)
    }
}

private struct CategoryInlineEditor: View {
    @ScaledMetric(relativeTo: .caption) private var sectionSpacing = 12
    @ScaledMetric(relativeTo: .caption2) private var itemWidth = 58
    @ScaledMetric(relativeTo: .caption2) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .caption2) private var estimatedItemHeight = 62
    @ScaledMetric(relativeTo: .caption2) private var textSpacing = 6
    @ScaledMetric(relativeTo: .caption2) private var iconSize = 38
    @ScaledMetric(relativeTo: .caption2) private var iconFontSize = 15
    @ScaledMetric(relativeTo: .caption2) private var verticalPadding = 4

    @Binding var selection: String
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text(L("Category"))

            JustifiedGrid(items: expenseCategories, id: \.id, itemWidth: itemWidth, rowSpacing: rowSpacing, estimatedItemHeight: estimatedItemHeight) { category in
                Button {
                    onEdit()
                    selection = category.id
                } label: {
                    VStack(spacing: textSpacing) {
                        Image(systemName: category.symbol)
                            .font(.system(size: iconFontSize, weight: .semibold))
                            .foregroundStyle(category.color)
                            .frame(width: iconSize, height: iconSize)
                            .background(category.color.opacity(0.13), in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(selection == category.id ? SoftLedgerTheme.accent : Color.clear, lineWidth: max(1.5, iconSize / 19))
                            }

                        Text(L(category.titleKey))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selection == category.id ? SoftLedgerTheme.ink : SoftLedgerTheme.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: itemWidth)
                    }
                    .frame(width: itemWidth)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, verticalPadding)
    }
}

private struct JustifiedGrid<Item, ID: Hashable, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let itemWidth: CGFloat
    let rowSpacing: CGFloat
    let estimatedItemHeight: CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        GeometryReader { proxy in
            let columns = columnCount(for: proxy.size.width)
            let spacing = itemSpacing(for: proxy.size.width, columns: columns)
            let rows = items.chunks(of: columns)

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: id) { item in
                            content(item)
                        }

                        if row.count < columns {
                            ForEach(0..<(columns - row.count), id: \.self) { _ in
                                Color.clear.frame(width: itemWidth)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        let columns = 5
        let rowCount = CGFloat((items.count + columns - 1) / columns)
        return rowCount * estimatedItemHeight + max(rowCount - 1, 0) * rowSpacing
    }

    private func columnCount(for width: CGFloat) -> Int {
        max(1, min(5, Int((width + 10) / (itemWidth + 10))))
    }

    private func itemSpacing(for width: CGFloat, columns: Int) -> CGFloat {
        guard columns > 1 else { return 0 }
        return max(10, (width - CGFloat(columns) * itemWidth) / CGFloat(columns - 1))
    }
}

struct BalancesWorkspace: View {
    @EnvironmentObject private var store: WalkcalcStore
    let group: WalkGroup
    let initialMember: Member?
    @State private var path: [Member] = []

    private var currentGroup: WalkGroup {
        store.group(id: group.id) ?? group
    }

    var body: some View {
        NavigationStack(path: $path) {
            BalancesRootView(group: currentGroup) { member in
                path.append(member)
            }
            .navigationDestination(for: Member.self) { member in
                MemberBalanceDetailView(group: currentGroup, member: member)
            }
        }
        .onAppear {
            if let initialMember, path.isEmpty {
                path = [initialMember]
            }
        }
    }
}

private struct BalancesRootView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @State private var showsResolveConfirmation = false
    @State private var pendingResolveMode = ResolveMode.all
    @State private var pendingResolveDebts: [ResolvedDebt] = []
    @ScaledMetric(relativeTo: .headline) private var sectionSpacing = 9
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var rowVerticalPadding = 4
    @ScaledMetric(relativeTo: .subheadline) private var dividerLeadingPadding = 54
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius = 16
    @ScaledMetric(relativeTo: .body) private var horizontalPadding = 20
    @ScaledMetric(relativeTo: .caption) private var topPadding = 8
    @ScaledMetric(relativeTo: .body) private var bottomPadding = 82
    @ScaledMetric(relativeTo: .body) private var resolveButtonBottomPadding = 14

    let group: WalkGroup
    let onSelect: (Member) -> Void

    private var members: [Member] {
        group.allMembers
    }

    private var debts: [ResolvedDebt] {
        store.resolvedDebts(for: group)
    }

    private var resolveAllTitle: String {
        L("Resolve all transfer")
    }

    private var pendingResolveTitle: String {
        switch pendingResolveMode {
        case .all:
            return L("Resolve all transfer")
        case .single:
            return L("Resolve transfer?")
        }
    }

    private var resolveConfirmationTitle: String {
        if pendingResolveMode == .single {
            return pendingResolveTitle
        }
        return "\(pendingResolveTitle)?"
    }

    private var resolveConfirmationMessage: String {
        guard pendingResolveMode == .single,
              let debt = pendingResolveDebts.first else {
            return ""
        }
        return String(
            format: L("%@ should pay %@ %@"),
            debt.from.name,
            debt.to.name,
            "¥\(Money.display(debt.amountMinor))"
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SoftLedgerBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        Text(L("All balances"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.ink)

                        LazyVStack(spacing: 0) {
                            ForEach(members) { member in
                                BalancePreviewRow(member: member, recordCount: recordCount(for: member)) {
                                    onSelect(member)
                                }
                                if member.id != members.last?.id {
                                    Divider()
                                        .overlay(SoftLedgerTheme.rule.opacity(0.54))
                                        .padding(.leading, dividerLeadingPadding)
                                }
                            }
                        }
                        .padding(.horizontal, rowHorizontalPadding)
                        .padding(.vertical, rowVerticalPadding)
                        .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                        }
                    }

                    if !debts.isEmpty {
                        SettlementPlanSection(debts: debts) { debt in
                            pendingResolveMode = .single
                            pendingResolveDebts = [debt]
                            showsResolveConfirmation = true
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }

            if !debts.isEmpty {
                Button(resolveAllTitle) {
                    pendingResolveMode = .all
                    pendingResolveDebts = debts
                    showsResolveConfirmation = true
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.bottom, resolveButtonBottomPadding)
            }
        }
        .navigationTitle(L("Balances"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(SoftLedgerTheme.accent)
        .task(id: group.id) {
            await store.refreshGroupBalances(group.id)
            await store.refreshSettlementSuggestion(groupId: group.id)
        }
        .alert(resolveConfirmationTitle, isPresented: $showsResolveConfirmation) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Resolve")) {
                let debtsToResolve = pendingResolveDebts
                let resolveMode = pendingResolveMode
                pendingResolveDebts = []
                pendingResolveMode = .all

                Task {
                    switch resolveMode {
                    case .all:
                        _ = await store.resolveAll(groupId: group.id, debts: debtsToResolve)
                    case .single:
                        guard let debt = debtsToResolve.first else { return }
                        _ = await store.resolveSingle(groupId: group.id, debt: debt)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(pendingResolveDebts.isEmpty)
        } message: {
            if !resolveConfirmationMessage.isEmpty {
                Text(resolveConfirmationMessage)
            }
        }
    }

    private func recordCount(for member: Member) -> Int {
        if member.recordCount > 0 {
            return member.recordCount
        }
        return (store.recordsByGroup[group.id] ?? []).filter { record in
            record.who == member.uuid || record.forWhom.contains(member.uuid)
        }.count
    }

    private enum ResolveMode {
        case all
        case single
    }
}

private struct SettlementPlanSection: View {
    @ScaledMetric(relativeTo: .headline) private var sectionSpacing = 9
    @ScaledMetric(relativeTo: .subheadline) private var cardSpacing = 10

    let debts: [ResolvedDebt]
    let onResolve: (ResolvedDebt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text(L("Suggested settlement"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)

            LazyVStack(spacing: cardSpacing) {
                ForEach(debts) { debt in
                    SettlementPlanRow(debt: debt) {
                        onResolve(debt)
                    }
                }
            }
        }
    }
}

private struct SettlementPlanRow: View {
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 30
    @ScaledMetric(relativeTo: .caption) private var receiverAvatarSize = 20
    @ScaledMetric(relativeTo: .caption) private var arrowBadgeSize = 18
    @ScaledMetric(relativeTo: .caption2) private var arrowBadgeFontSize = 9
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .caption) private var textSpacing = 4
    @ScaledMetric(relativeTo: .caption) private var receiverSpacing = 6
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var cardHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var cardVerticalPadding = 12
    @ScaledMetric(relativeTo: .subheadline) private var amountMinWidth = 76
    @ScaledMetric(relativeTo: .subheadline) private var chevronSize = 14
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius = 16

    let debt: ResolvedDebt
    let onResolve: () -> Void

    var body: some View {
        Button(action: onResolve) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(debt.from.name) \(L("pays")) \(debt.to.name), ¥\(Money.display(debt.amountMinor))")
        .accessibilityHint(L("Resolve this transfer"))
    }

    private var rowContent: some View {
        HStack(spacing: rowSpacing) {
            payerAvatar

            VStack(alignment: .leading, spacing: textSpacing) {
                Text("\(debt.from.name) \(L("pays")) \(debt.to.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .truncationMode(.tail)

                HStack(spacing: receiverSpacing) {
                    SoftLedgerAvatar(member: debt.to, size: receiverAvatarSize)
                        .accessibilityHidden(true)

                    Text(L("Settle with %@").replacingOccurrences(of: "%@", with: debt.to.name))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: rowSpacing)

            Text("¥\(Money.compactDisplay(debt.amountMinor))")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .frame(minWidth: amountMinWidth, alignment: .trailing)
                .layoutPriority(3)

            Image(systemName: "chevron.right")
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundStyle(SoftLedgerTheme.secondaryInk.opacity(0.64))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, cardHorizontalPadding)
        .padding(.vertical, cardVerticalPadding)
        .frame(minHeight: rowMinHeight)
        .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
        }
    }

    private var payerAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            SoftLedgerAvatar(member: debt.from, size: avatarSize)
                .accessibilityHidden(true)

            Image(systemName: "arrow.right")
                .font(.system(size: arrowBadgeFontSize, weight: .bold))
                .foregroundStyle(SoftLedgerTheme.paper)
                .frame(width: arrowBadgeSize, height: arrowBadgeSize)
                .background(SoftLedgerTheme.accent, in: Circle())
                .overlay {
                    Circle()
                        .stroke(SoftLedgerTheme.paper, lineWidth: max(1, arrowBadgeSize / 9))
                }
                .offset(x: 2, y: 2)
                .accessibilityHidden(true)
        }
        .frame(width: avatarSize + 3, height: avatarSize + 3)
    }
}

private struct MemberBalanceDetailView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .title) private var balanceFontSize = 36
    @ScaledMetric(relativeTo: .body) private var summaryPadding = 18
    @ScaledMetric(relativeTo: .caption) private var summarySpacing = 5
    @ScaledMetric(relativeTo: .headline) private var sectionSpacing = 10
    @ScaledMetric(relativeTo: .subheadline) private var emptyRowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var rowVerticalPadding = 4
    @ScaledMetric(relativeTo: .subheadline) private var compactRowHorizontalPadding = 12
    @ScaledMetric(relativeTo: .subheadline) private var dividerLeadingPadding = 48
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius = 16
    @ScaledMetric(relativeTo: .body) private var horizontalPadding = 20
    @ScaledMetric(relativeTo: .caption) private var topPadding = 8
    @ScaledMetric(relativeTo: .body) private var bottomPadding = 28

    let group: WalkGroup
    let member: Member
    @State private var selectedRecord: WalkRecord?
    @State private var deleteCandidate: WalkRecord?

    private var currentGroup: WalkGroup {
        store.group(id: group.id) ?? group
    }

    private var currentMember: Member {
        currentGroup.allMembers.first(where: { $0.uuid == member.uuid }) ?? member
    }

    private var records: [WalkRecord] {
        store.memberRecords(groupId: group.id, memberId: member.uuid)
    }

    private var recordTotal: Int {
        store.memberRecordTotal(groupId: group.id, memberId: member.uuid)
    }

    private var balanceTextColor: Color {
        Money.isZero(currentMember.debtMinor) ? SoftLedgerTheme.ink : moneyColor(currentMember.debtMinor)
    }

    var body: some View {
        ZStack {
            SoftLedgerBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: summarySpacing) {
                            Text(L("Balance with %@").replacingOccurrences(of: "%@", with: currentMember.name))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                            Text(signedMoney(currentMember.debtMinor, style: .exact))
                                .font(.system(size: balanceFontSize, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(balanceTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        Spacer()
                        Text(L("%@ records").replacingOccurrences(of: "%@", with: "\(recordTotal)"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.mutedInk)
                    }
                    .padding(summaryPadding)
                    .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        Text(L("Records"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.ink)

                        if records.isEmpty {
                            Text(L("No records yet"))
                                .font(.subheadline)
                                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                                .frame(maxWidth: .infinity, minHeight: emptyRowMinHeight, alignment: .leading)
                                .padding(.horizontal, rowHorizontalPadding)
                                .padding(.vertical, rowVerticalPadding)
                                .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                                }
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(records) { record in
                                    ExpenseRow(record: record, group: currentGroup, onDelete: {
                                        deleteCandidate = record
                                    }) {
                                        selectedRecord = record
                                    }
                                    if record.id != records.last?.id {
                                        Divider()
                                            .overlay(SoftLedgerTheme.rule.opacity(0.52))
                                            .padding(.leading, dividerLeadingPadding)
                                    }
                                }

                                if store.isLoadingMemberRecords(groupId: group.id, memberId: member.uuid) {
                                    Divider()
                                        .overlay(SoftLedgerTheme.rule.opacity(0.52))
                                        .padding(.leading, dividerLeadingPadding)
                                    memberLoadMoreFooter
                                }
                            }
                            .padding(.horizontal, compactRowHorizontalPadding)
                            .padding(.vertical, rowVerticalPadding)
                            .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                let triggerY = max(0, geometry.contentSize.height - 160)
                return visibleBottom >= triggerY
            } action: { _, isNearBottom in
                guard isNearBottom else { return }
                guard store.canLoadMoreMemberRecords(groupId: group.id, memberId: member.uuid),
                      !store.isLoadingMemberRecords(groupId: group.id, memberId: member.uuid) else { return }
                Task { await store.loadMoreMemberRecords(groupId: group.id, memberId: member.uuid) }
            }
        }
        .navigationTitle(currentMember.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await store.refreshMemberRecords(groupId: group.id, memberId: member.uuid)
        }
        .navigationDestination(item: $selectedRecord) { record in
            RecordEditorView(groupId: group.id, record: record) {
                selectedRecord = nil
            }
        }
        .recordDeleteConfirmation(groupId: group.id, record: $deleteCandidate) { deletedRecord in
            if selectedRecord?.recordId == deletedRecord.recordId {
                selectedRecord = nil
            }
        }
    }

    private var memberLoadMoreFooter: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L("Loading more..."))
                .font(.subheadline)
                .foregroundStyle(SoftLedgerTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: emptyRowMinHeight, alignment: .leading)
    }
}

struct SSOProfileView: View {
    let url: URL
    let token: String?

    var body: some View {
        WebView(url: url, token: token, injectAuthCookie: true, onToken: nil)
    }
}
