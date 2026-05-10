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
                .presentationDetents([.medium, .large])
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
    @State private var tempMemberName = ""
    @State private var isShowingAddTemporaryMember = false

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

    private var canAddTempMember: Bool {
        !tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section(L("Group")) {
                TextField(L("Name"), text: $groupName)
                    .textInputAutocapitalization(.words)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Initial members")) {
                HStack {
                    Text(L("Members"))
                    Spacer()
                    SoftLedgerAvatarStack(members: members, visibleCount: 4, borderColor: SoftLedgerTheme.formPaper, showsTotal: true)
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

                Button {
                    isShowingAddTemporaryMember = true
                } label: {
                    Text(L("Add temporary member"))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Create group"))
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
        .alert(L("Add temporary member"), isPresented: $isShowingAddTemporaryMember) {
            TextField(L("Name"), text: $tempMemberName)

            Button(L("Cancel"), role: .cancel) {
                tempMemberName = ""
            }

            Button(L("Add")) {
                let name = tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, !tempUsers.contains(name) {
                    tempUsers.append(name)
                }
                tempMemberName = ""
            }
            .disabled(!canAddTempMember)
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let archivedGroups: [WalkGroup]
    let onDone: () -> Void
    @State private var confirmLogout = false
    @State private var showingProfile = false

    var body: some View {
        Form {
            Section(L("Account")) {
                HStack(spacing: 12) {
                    SoftLedgerAvatar(user: store.user, size: 32)
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
        }
    }
}

struct ArchivedGroupsView: View {
    @EnvironmentObject private var store: WalkcalcStore
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
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SoftLedgerTheme.ink)
                                    .lineLimit(1)
                                Text(DateFormatter.walkDate.string(from: group.modifiedAt.walkDate))
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
                                    .padding(.horizontal, 6)
                                    .frame(minHeight: 44)
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
    @State private var tempMemberName = ""
    @State private var isShowingAddTemporaryMember = false
    @State private var confirmation: GroupSettingsConfirmation?

    init(group: WalkGroup, onDone: @escaping () -> Void, onArchive: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.group = group
        self.onDone = onDone
        self.onArchive = onArchive
        self.onDelete = onDelete
        _name = State(initialValue: group.name)
    }

    private var canAddTempMember: Bool {
        !tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section(L("Group")) {
                TextField(L("Name"), text: $name)
                    .textInputAutocapitalization(.words)

                HStack {
                    Text(L("Group ID"))
                    Spacer()
                    Text(group.id)
                        .font(.body.monospaced())
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .textSelection(.enabled)
                }

                HStack {
                    Text(L("Members"))
                    Spacer()
                    SoftLedgerAvatarStack(members: group.allMembers, visibleCount: 4, borderColor: SoftLedgerTheme.formPaper, showsTotal: true)
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Members")) {
                NavigationLink {
                    AddMemberSearchView(existingMemberIds: Set(group.allMembers.map(\.uuid))) { users in
                        Task {
                            _ = await store.addMembers(groupId: group.id, users: users, tempUsers: [])
                        }
                    }
                } label: {
                    Text(L("Add member"))
                        .foregroundStyle(.primary)
                }

                Button {
                    isShowingAddTemporaryMember = true
                } label: {
                    Text(L("Add temporary member"))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Management")) {
                Button {
                    confirmation = .archive
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
        .alert(L("Add temporary member"), isPresented: $isShowingAddTemporaryMember) {
            TextField(L("Name"), text: $tempMemberName)
            Button(L("Cancel"), role: .cancel) { tempMemberName = "" }
            Button(L("Add")) {
                let value = tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
                tempMemberName = ""
                Task { _ = await store.addMembers(groupId: group.id, users: [], tempUsers: [value]) }
            }
            .disabled(!canAddTempMember)
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

struct PeopleSetupSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let group: WalkGroup
    let onDone: () -> Void
    @State private var tempMemberName = ""
    @State private var isShowingAddTemporaryMember = false

    private var canAddTempMember: Bool {
        !tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

                Button {
                    isShowingAddTemporaryMember = true
                } label: {
                    Text(L("Add temporary member"))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .alert(L("Add temporary member"), isPresented: $isShowingAddTemporaryMember) {
            TextField(L("Name"), text: $tempMemberName)
            Button(L("Cancel"), role: .cancel) { tempMemberName = "" }
            Button(L("Add")) {
                let value = tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
                tempMemberName = ""
                Task {
                    if await store.addMembers(groupId: group.id, users: [], tempUsers: [value]) {
                        dismiss()
                        onDone()
                    }
                }
            }
            .disabled(!canAddTempMember)
        }
    }
}

struct AddMemberSearchView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let existingMemberIds: Set<String>
    let onAdd: ([UserProfile]) -> Void

    @State private var searchText = ""
    @State private var results: [UserProfile] = []
    @State private var selectedUsers: [UserProfile] = []
    @State private var isSearching = false

    private var canAdd: Bool {
        !selectedUsers.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Search by name"), text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section(L("Results")) {
                if isSearching {
                    ProgressView()
                }
                ForEach(results.filter { !existingMemberIds.contains($0.uuid) }) { user in
                    Button {
                        toggle(user)
                    } label: {
                        HStack(spacing: 12) {
                            SoftLedgerAvatar(user: user, size: 30)
                            Text(user.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedUsers.contains(user) {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SoftLedgerTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            if !selectedUsers.isEmpty {
                Section(L("Selected")) {
                    Text(selectedUsers.map(\.name).joined(separator: ", "))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                }
                .listRowBackground(SoftLedgerTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .tint(SoftLedgerTheme.accent)
        .navigationTitle(L("Add member"))
        .navigationBarTitleDisplayMode(.inline)
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
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                results = []
                isSearching = false
                return
            }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = await store.searchUsers(name: query)
            isSearching = false
        }
    }

    private func toggle(_ user: UserProfile) {
        if let index = selectedUsers.firstIndex(of: user) {
            selectedUsers.remove(at: index)
        } else {
            selectedUsers.append(user)
        }
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
    @State private var confirmDelete = false

    init(groupId: String, record: WalkRecord? = nil, onDone: @escaping () -> Void) {
        self.groupId = groupId
        self.record = record
        self.onDone = onDone
        _amount = State(initialValue: record.map { Money.editableDisplay($0.paidMinor) } ?? "")
        _paidBy = State(initialValue: record?.who ?? "")
        _splitMembers = State(initialValue: Set(record?.forWhom ?? []))
        _categoryId = State(initialValue: record?.type ?? "food")
        _note = State(initialValue: record?.text ?? "")
        _date = State(initialValue: record?.createdAt.walkDate ?? Date())
    }

    private var group: WalkGroup? {
        store.group(id: groupId)
    }

    private var members: [Member] {
        group?.allMembers ?? []
    }

    private var title: String {
        record == nil ? L("New expense") : L("Edit expense")
    }

    private var canSave: Bool {
        (try? Money.parseDisplay(amount)).map { !Money.isZero($0) } == true
            && !paidBy.isEmpty
            && !splitMembers.isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("¥")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
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
                Picker(L("Paid by"), selection: $paidBy) {
                    ForEach(members) { member in
                        Text(member.name).tag(member.uuid)
                    }
                }
                .pickerStyle(.menu)

                SplitInlineEditor(members: members, selection: $splitMembers)
                CategoryInlineEditor(selection: $categoryId)

                DatePicker(L("Date"), selection: $date)
                    .datePickerStyle(.compact)

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
                        confirmDelete = true
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
        .task {
            if paidBy.isEmpty {
                paidBy = store.user?.uuid ?? members.first?.uuid ?? ""
            }
            focusedField = .amount
        }
        .overlay {
            KeyboardDismissTapLayer(isActive: focusedField != nil) {
                focusedField = nil
            }
            .frame(width: 0, height: 0)
        }
        .alert(L("Confirm delete?"), isPresented: $confirmDelete) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete"), role: .destructive) {
                if let record {
                    Task {
                        if await store.deleteRecord(groupId: groupId, recordId: record.recordId) {
                            dismiss()
                            onDone()
                        }
                    }
                }
            }
        }
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
                text: note
            )
        } else {
            success = await store.addRecord(
                groupId: groupId,
                who: paidBy,
                paid: amount,
                forWhom: Array(splitMembers),
                type: categoryId,
                text: note
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

private enum ExpenseEditorField {
    case amount
    case note
}

private struct KeyboardDismissTapLayer: UIViewRepresentable {
    let isActive: Bool
    let dismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        KeyboardDismissTapView(isActive: isActive, dismiss: dismiss)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let uiView = uiView as? KeyboardDismissTapView else { return }
        uiView.isActive = isActive
        uiView.dismiss = dismiss
    }

    final class KeyboardDismissTapView: UIView, UIGestureRecognizerDelegate {
        var isActive: Bool
        var dismiss: () -> Void
        private weak var installedWindow: UIWindow?
        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        init(isActive: Bool, dismiss: @escaping () -> Void) {
            self.isActive = isActive
            self.dismiss = dismiss
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if installedWindow !== window {
                installedWindow?.removeGestureRecognizer(recognizer)
                installedWindow = window
                window?.addGestureRecognizer(recognizer)
            }
        }

        deinit {
            installedWindow?.removeGestureRecognizer(recognizer)
        }

        @objc func handleTap() {
            guard isActive else { return }
            dismiss()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isActive else { return false }
            var touchedView: UIView? = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }
    }
}

private struct SplitInlineEditor: View {
    let members: [Member]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Split"))
                Spacer()
                Button(L("All")) {
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

            JustifiedGrid(items: members, id: \.id, itemWidth: 56, rowSpacing: 10, estimatedItemHeight: 58) { member in
                Button {
                    toggle(member)
                } label: {
                    VStack(spacing: 5) {
                        SelectableSplitAvatar(member: member, isSelected: selection.contains(member.uuid))

                        Text(member.name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SoftLedgerTheme.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: 56)
                    }
                    .frame(width: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SoftLedgerAvatar(member: member, size: 36)
                .overlay {
                    Circle()
                        .stroke(isSelected ? SoftLedgerTheme.accent : SoftLedgerTheme.rule.opacity(0.45), lineWidth: isSelected ? 2 : 1)
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
                    .frame(width: 15, height: 15)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 38, height: 38)
    }
}

private struct CategoryInlineEditor: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Category"))

            JustifiedGrid(items: expenseCategories, id: \.id, itemWidth: 58, rowSpacing: 12, estimatedItemHeight: 62) { category in
                Button {
                    selection = category.id
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(category.color)
                            .frame(width: 38, height: 38)
                            .background(category.color.opacity(0.13), in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(selection == category.id ? SoftLedgerTheme.accent : Color.clear, lineWidth: 2)
                            }

                        Text(L(category.titleKey))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selection == category.id ? SoftLedgerTheme.ink : SoftLedgerTheme.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: 58)
                    }
                    .frame(width: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
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

    var body: some View {
        NavigationStack(path: $path) {
            BalancesRootView(group: group) { member in
                path.append(member)
            }
            .navigationDestination(for: Member.self) { member in
                MemberBalanceDetailView(group: group, member: member)
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
    let group: WalkGroup
    let onSelect: (Member) -> Void

    private var members: [Member] {
        group.allMembers.filter { $0.uuid != store.user?.uuid }
    }

    private var debts: [ResolvedDebt] {
        store.resolvedDebts(for: group)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SoftLedgerBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        ForEach(members) { member in
                            BalancePreviewRow(member: member, recordCount: recordCount(for: member)) {
                                onSelect(member)
                            }
                            if member.id != members.last?.id {
                                Divider()
                                    .overlay(SoftLedgerTheme.rule.opacity(0.54))
                                    .padding(.leading, 54)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                    }

                    if !debts.isEmpty {
                        SettlementPlanSection(debts: debts)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 82)
            }

            if !debts.isEmpty {
                Button(L("Resolve %@ transfers").replacingOccurrences(of: "%@", with: "\(debts.count)")) {
                    Task { _ = await store.resolveAll(groupId: group.id, debts: debts) }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.bottom, 14)
            }
        }
        .navigationTitle(L("Balances"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func recordCount(for member: Member) -> Int {
        (store.recordsByGroup[group.id] ?? []).filter { record in
            record.who == member.uuid || record.forWhom.contains(member.uuid)
        }.count
    }
}

private struct SettlementPlanSection: View {
    let debts: [ResolvedDebt]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("Suggested settlement"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)

            VStack(spacing: 0) {
                ForEach(debts) { debt in
                    HStack(spacing: 12) {
                        Text("\(debt.from.name) \(L("pays")) \(debt.to.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("¥\(Money.compactDisplay(debt.amountMinor))")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.ink)
                    }
                    .frame(minHeight: 54)

                    if debt.id != debts.last?.id {
                        Divider()
                            .overlay(SoftLedgerTheme.rule.opacity(0.54))
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
    }
}

private struct MemberBalanceDetailView: View {
    @EnvironmentObject private var store: WalkcalcStore
    let group: WalkGroup
    let member: Member
    @State private var editingRecord: WalkRecord?

    private var records: [WalkRecord] {
        (store.recordsByGroup[group.id] ?? []).filter { record in
            record.who == member.uuid || record.forWhom.contains(member.uuid)
        }
    }

    var body: some View {
        ZStack {
            SoftLedgerBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("Balance with %@").replacingOccurrences(of: "%@", with: member.name))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                            Text(signedMoney(member.debtMinor))
                                .font(.system(size: 36, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(moneyColor(member.debtMinor))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        Spacer()
                        Text(L("%@ records").replacingOccurrences(of: "%@", with: "\(records.count)"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.mutedInk)
                    }
                    .padding(18)
                    .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Records"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.ink)

                        if records.isEmpty {
                            Text(L("No records yet"))
                                .font(.subheadline)
                                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                                }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(records) { record in
                                    ExpenseRow(record: record, group: group) {
                                        editingRecord = record
                                    }
                                    if record.id != records.last?.id {
                                        Divider()
                                            .overlay(SoftLedgerTheme.rule.opacity(0.52))
                                            .padding(.leading, 48)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $editingRecord) { record in
            NavigationStack {
                RecordEditorView(groupId: group.id, record: record) {
                    editingRecord = nil
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct SSOProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let token: String?

    var body: some View {
        NavigationStack {
            WebView(url: url, token: token, injectAuthCookie: true, onToken: nil)
                .navigationTitle(L("My Profile"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Cancel")) { dismiss() }
                    }
                }
        }
    }
}
