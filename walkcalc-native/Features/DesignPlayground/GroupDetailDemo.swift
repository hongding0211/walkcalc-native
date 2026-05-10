import SwiftUI
import UIKit

private struct GroupDetailScenario {
    let title: String
    let myBalance: String
    let memberInitials: [String]
    let debts: [GroupDetailMockDebt]
    let records: [GroupDetailMockRecord]

    var shouldShowPeopleSetup: Bool {
        memberInitials.count == 1 && records.isEmpty
    }

    static let populated = GroupDetailScenario(
        title: "May Trip",
        myBalance: "+¥86.20",
        memberInitials: ["H", "L", "M", "Y"],
        debts: GroupDetailMockDebt.samples,
        records: GroupDetailMockRecord.samples
    )

    static let peopleSetupEmpty = GroupDetailScenario(
        title: "New group",
        myBalance: "¥0.00",
        memberInitials: ["H"],
        debts: [],
        records: []
    )
}

private struct SoftLedgerGroupDetailPlayground: View {
    @State private var isShowingBalances = false
    @State private var isShowingNewExpense = false
    @State private var isShowingGroupSettings = false
    @State private var isShowingPeopleSetup = false
    @State private var editingRecord: GroupDetailMockRecord?
    @State private var initialBalanceMemberName: String?
    @State private var searchText = ""

    let scenario: GroupDetailScenario

    init(scenario: GroupDetailScenario = .populated) {
        self.scenario = scenario
    }

    private var debts: [GroupDetailMockDebt] {
        scenario.debts
    }

    private var records: [GroupDetailMockRecord] {
        scenario.records
    }

    var body: some View {
        ZStack {
            GroupDetailTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if scenario.shouldShowPeopleSetup {
                        GroupDetailPeopleSetupEmptyState {
                            isShowingPeopleSetup = true
                        }
                    } else {
                        GroupDetailSummaryCard(
                            balance: scenario.myBalance,
                            memberInitials: scenario.memberInitials
                        )
                        GroupDetailDebtSection(
                            debts: debts,
                            onShowDetails: showBalances,
                            onSelectDebt: showBalanceDetails
                        )
                        GroupDetailRecordSection(records: records) { record in
                            editingRecord = record
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $isShowingBalances, onDismiss: {
            initialBalanceMemberName = nil
        }) {
            GroupDetailBalancesWorkspace(initialMemberName: initialBalanceMemberName)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingNewExpense) {
            NavigationStack {
                GroupDetailNewExpenseSheet(mode: .new)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingGroupSettings) {
            NavigationStack {
                GroupDetailSettingsSheet()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingPeopleSetup) {
            NavigationStack {
                GroupDetailPeopleSetupSheet()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingRecord) { record in
            NavigationStack {
                GroupDetailNewExpenseSheet(mode: .edit(record))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingGroupSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Group settings")
            }

            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    isShowingNewExpense = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Add expense")
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func showBalances() {
        initialBalanceMemberName = nil
        isShowingBalances = true
    }

    private func showBalanceDetails(_ debt: GroupDetailMockDebt) {
        initialBalanceMemberName = debt.name
        isShowingBalances = true
    }
}

private enum GroupDetailBalanceRoute: Hashable {
    case member(String)
}

private struct GroupDetailBalancesWorkspace: View {
    @State private var path: [GroupDetailBalanceRoute]

    let initialMemberName: String?

    init(initialMemberName: String?) {
        self.initialMemberName = initialMemberName
        _path = State(initialValue: initialMemberName.map { [.member($0)] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            GroupDetailAllBalancesPlayground { debt in
                path.append(.member(debt.name))
            }
            .navigationDestination(for: GroupDetailBalanceRoute.self) { route in
                switch route {
                case .member(let memberName):
                    GroupDetailMemberBalancePlayground(memberName: memberName)
                }
            }
        }
    }
}

private struct GroupDetailAllBalancesPlayground: View {
    private let debts = GroupDetailMockDebt.samples
    let onSelectDebt: (GroupDetailMockDebt) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            GroupDetailTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupDetailAllBalancesList(debts: debts, onSelectDebt: onSelectDebt)
                    GroupDetailSettlementPlanSection()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }

            GroupDetailResolveTransfersButton()
                .padding(.bottom, 14)
        }
        .navigationTitle("Balances")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private enum GroupDetailNewExpenseField {
    case amount
    case note
}

private enum GroupDetailSettingsConfirmation: Identifiable {
    case archive
    case delete

    var id: String {
        switch self {
        case .archive:
            "archive"
        case .delete:
            "delete"
        }
    }
}

private struct GroupDetailSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let groupID = "GRP-MAY-8K2"

    @State private var groupName = "May Trip"
    @State private var tempMemberName = ""
    @State private var isShowingAddTemporaryMember = false
    @State private var confirmation: GroupDetailSettingsConfirmation?

    @State private var members = ["Hong", "Lin", "Ming", "Yan", "Ava", "Kai"]

    private var canAddTempMember: Bool {
        !tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Group") {
                TextField("Name", text: $groupName)
                    .textInputAutocapitalization(.words)

                HStack {
                    Text("Group ID")
                    Spacer()
                    Text(groupID)
                        .font(.body.monospaced())
                        .foregroundStyle(GroupDetailTheme.secondaryInk)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("Members")
                    Spacer()
                    GroupDetailSettingsMemberStack(members: members, visibleCount: 4)
                }
            }
            .listRowBackground(GroupDetailTheme.formPaper)

            Section("People") {
                NavigationLink {
                    GroupDetailAddMemberSheet(existingMembers: members) { addedMembers in
                        members.append(contentsOf: addedMembers)
                    }
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
            .listRowBackground(GroupDetailTheme.formPaper)

            Section("Management") {
                Button {
                    confirmation = .archive
                } label: {
                    Text("Archive group")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    confirmation = .delete
                } label: {
                    Text("Delete group")
                }
            }
            .listRowBackground(GroupDetailTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .tint(GroupDetailTheme.accent)
        .navigationTitle("Group settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(GroupDetailTheme.accent)
                .accessibilityLabel("Done")
            }
        }
        .alert("Add temporary member", isPresented: $isShowingAddTemporaryMember) {
            TextField("Name", text: $tempMemberName)

            Button("Cancel", role: .cancel) {
                tempMemberName = ""
            }

            Button("Add") {
                let name = tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    members.append(name)
                }
                tempMemberName = ""
            }
            .disabled(!canAddTempMember)
        } message: {
            Text("Temporary members can participate in expenses without an account.")
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            switch confirmation {
            case .archive:
                Button("Archive group") {
                    confirmation = nil
                    dismiss()
                }
            case .delete:
                Button("Delete group", role: .destructive) {
                    confirmation = nil
                    dismiss()
                }
            case nil:
                EmptyView()
            }

            Button("Cancel", role: .cancel) {
                confirmation = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .archive:
            "Archive group?"
        case .delete:
            "Delete group?"
        case nil:
            ""
        }
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .archive:
            "Archived groups leave the active list but keep their history."
        case .delete:
            "This removes the group and its records from this demo."
        case nil:
            ""
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { isPresented in
                if !isPresented {
                    confirmation = nil
                }
            }
        )
    }
}

private struct GroupDetailSettingsMemberStack: View {
    let members: [String]
    let visibleCount: Int

    private var visibleMembers: [String] {
        Array(members.prefix(visibleCount))
    }

    private var hiddenCount: Int {
        max(members.count - visibleMembers.count, 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(visibleMembers, id: \.self) { member in
                    GroupDetailAvatar(initial: String(member.prefix(1)), size: 28)
                        .overlay {
                            Circle().stroke(GroupDetailTheme.formPaper, lineWidth: 2)
                        }
                }

                if hiddenCount > 0 {
                    Circle()
                        .fill(GroupDetailTheme.canvas)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text("+\(hiddenCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(GroupDetailTheme.secondaryInk)
                        }
                        .overlay {
                            Circle().stroke(GroupDetailTheme.formPaper, lineWidth: 2)
                        }
                }
            }

            Text("\(members.count) total")
                .font(.subheadline)
                .foregroundStyle(GroupDetailTheme.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(members.count) members")
    }
}

private struct GroupDetailAddMemberSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingMembers: [String]
    let onAdd: ([String]) -> Void

    @State private var searchText = ""
    @State private var selectedMembers: Set<String> = []

    private let candidates = ["Alexandra", "Christopher", "Noah", "Ivy", "Owen", "Tara", "June", "Keith"]

    private var availableCandidates: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { candidate in
            !existingMembers.contains(candidate)
                && (query.isEmpty || candidate.localizedCaseInsensitiveContains(query))
        }
    }

    private var canAdd: Bool {
        !selectedMembers.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Search by name", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .listRowBackground(GroupDetailTheme.formPaper)

            Section("Results") {
                ForEach(availableCandidates, id: \.self) { member in
                    Button {
                        toggle(member)
                    } label: {
                        HStack(spacing: 12) {
                            GroupDetailAvatar(initial: String(member.prefix(1)), size: 30)

                            Text(member)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedMembers.contains(member) {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(GroupDetailTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(GroupDetailTheme.formPaper)

            if !selectedMembers.isEmpty {
                Section("Selected") {
                    Text(selectedMembers.sorted().joined(separator: ", "))
                        .foregroundStyle(GroupDetailTheme.secondaryInk)
                }
                .listRowBackground(GroupDetailTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .tint(GroupDetailTheme.accent)
        .navigationTitle("Add member")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onAdd(selectedMembers.sorted())
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(GroupDetailTheme.accent)
                .disabled(!canAdd)
                .accessibilityLabel("Add")
            }
        }
    }

    private func toggle(_ member: String) {
        if selectedMembers.contains(member) {
            selectedMembers.remove(member)
        } else {
            selectedMembers.insert(member)
        }
    }
}

private struct GroupDetailPeopleSetupEmptyState: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(GroupDetailTheme.accent)
                .frame(width: 64, height: 64)
                .background(GroupDetailTheme.paper, in: Circle())
                .overlay {
                    Circle()
                        .stroke(GroupDetailTheme.rule.opacity(0.65), lineWidth: 1)
                }

            VStack(spacing: 6) {
                Text("Add people")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.ink)

                Text("Add members or temporary members when this becomes a shared expense group.")
                    .font(.callout)
                    .foregroundStyle(GroupDetailTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                action()
            } label: {
                Label("Add people", systemImage: "person.badge.plus")
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .accessibilityLabel("Add people")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}

private struct GroupDetailPeopleSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var tempMemberName = ""
    @State private var isShowingAddTemporaryMember = false

    private var canAddTempMember: Bool {
        !tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    GroupDetailAddMemberSheet(existingMembers: ["Hong"]) { _ in }
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
            .listRowBackground(GroupDetailTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .tint(GroupDetailTheme.accent)
        .navigationTitle("Add people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel")
            }
        }
        .alert("Add temporary member", isPresented: $isShowingAddTemporaryMember) {
            TextField("Name", text: $tempMemberName)

            Button("Cancel", role: .cancel) {
                tempMemberName = ""
            }

            Button("Add") {
                tempMemberName = ""
            }
            .disabled(!canAddTempMember)
        } message: {
            Text("Temporary members can participate in expenses without an account.")
        }
    }
}

private enum GroupDetailExpenseSheetMode {
    case new
    case edit(GroupDetailMockRecord)

    var title: String {
        switch self {
        case .new:
            "New expense"
        case .edit:
            "Edit expense"
        }
    }

    var isEditing: Bool {
        if case .edit = self {
            return true
        }
        return false
    }

    var amount: String {
        switch self {
        case .new:
            "123"
        case .edit(let record):
            record.amount.replacingOccurrences(of: "¥", with: "")
        }
    }

    var payer: String {
        switch self {
        case .new:
            "Hong"
        case .edit(let record):
            record.payer
        }
    }

    var category: String {
        switch self {
        case .new:
            "Meal"
        case .edit(let record):
            switch record.title {
            case "Hotel":
                "Hotel"
            case "Train tickets":
                "Transport"
            default:
                "Meal"
            }
        }
    }
}

private struct GroupDetailNewExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: GroupDetailNewExpenseField?

    let mode: GroupDetailExpenseSheetMode

    @State private var amount: String
    @State private var paidBy: String
    @State private var splitMembers: Set<String>
    @State private var category: String
    @State private var date = Date()
    @State private var note = ""

    private let members = ["Hong", "Lin", "Ming", "Yan", "Ava", "Christopher", "Alexandra", "Ivy", "Owen", "Tara"]
    private let categories = GroupDetailExpenseCategory.samples

    init(mode: GroupDetailExpenseSheetMode) {
        self.mode = mode
        _amount = State(initialValue: mode.amount)
        _paidBy = State(initialValue: mode.payer)
        _splitMembers = State(initialValue: [])
        _category = State(initialValue: mode.category)
    }

    private var canSave: Bool {
        let normalizedAmount = amount.replacingOccurrences(of: ",", with: "")
        let decimalAmount = Decimal(string: normalizedAmount) ?? 0
        return decimalAmount > 0
    }

    private var dateLabel: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        Form {
            Section {
                GroupDetailExpenseAmountField(amount: $amount)
                    .focused($focusedField, equals: .amount)
            }
            .listRowBackground(GroupDetailTheme.formPaper)

            Section {
                Picker("Paid by", selection: $paidBy) {
                    ForEach(members, id: \.self) { member in
                        Text(member).tag(member)
                    }
                }
                .pickerStyle(.menu)

                GroupDetailSplitInlineEditor(
                    members: members,
                    selection: $splitMembers
                )

                GroupDetailCategoryInlineEditor(
                    categories: categories,
                    selection: $category
                )

                DatePicker("Date", selection: $date)
                    .datePickerStyle(.compact)

                TextField("Optional note", text: $note, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .focused($focusedField, equals: .note)
            }
            .listRowBackground(GroupDetailTheme.formPaper)

            if mode.isEditing {
                Section {
                    Button(role: .destructive) {
                        dismiss()
                    } label: {
                        Text("Delete expense")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .accessibilityLabel("Delete expense")
                }
                .listRowBackground(GroupDetailTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .tint(GroupDetailTheme.accent)
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(GroupDetailTheme.accent)
                .disabled(!canSave)
                .accessibilityLabel("Save")
            }
        }
        .task {
            focusedField = .amount
        }
    }
}

private struct GroupDetailExpenseAmountField: View {
    @Binding var amount: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("¥")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(GroupDetailTheme.secondaryInk)

            TextField("0.00", text: $amount)
                .keyboardType(.decimalPad)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GroupDetailTheme.ink)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Amount")
    }
}

private struct GroupDetailSplitInlineEditor: View {
    let members: [String]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Split")
                Spacer()
                Button("All") {
                    if selection.count == members.count {
                        selection.removeAll()
                    } else {
                        selection = Set(members)
                    }
                }
                .font(.caption.weight(.semibold))
            }

            GroupDetailJustifiedGrid(items: members, id: \.self, itemWidth: 56, rowSpacing: 10) { member in
                Button {
                    toggle(member)
                } label: {
                    VStack(spacing: 5) {
                        Text(member.prefix(1))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection.contains(member) ? Color.white : GroupDetailTheme.secondaryInk)
                            .frame(width: 36, height: 36)
                            .background(
                                selection.contains(member) ? GroupDetailTheme.accent : GroupDetailTheme.canvas,
                                in: Circle()
                            )

                        Text(member)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(GroupDetailTheme.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: 56)
                    }
                    .frame(width: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(member)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ member: String) {
        if selection.contains(member) {
            selection.remove(member)
        } else {
            selection.insert(member)
        }
    }
}

private struct GroupDetailCategoryInlineEditor: View {
    let categories: [GroupDetailExpenseCategory]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")

            GroupDetailJustifiedGrid(items: categories, id: \.id, itemWidth: 58, rowSpacing: 12) { category in
                Button {
                    selection = category.title
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(category.color)
                            .frame(width: 38, height: 38)
                            .background(category.color.opacity(0.13), in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(selection == category.title ? GroupDetailTheme.accent : Color.clear, lineWidth: 2)
                            }

                        Text(category.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selection == category.title ? GroupDetailTheme.ink : GroupDetailTheme.secondaryInk)
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

private struct GroupDetailJustifiedGrid<Item, ID: Hashable, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let itemWidth: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        GeometryReader { proxy in
            let columns = columnCount(for: proxy.size.width)
            let spacing = itemSpacing(for: proxy.size.width, columns: columns)
            let rows = items.chunked(into: columns)

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: id) { item in
                            content(item)
                        }

                        if row.count < columns {
                            ForEach(0..<(columns - row.count), id: \.self) { _ in
                                Color.clear
                                    .frame(width: itemWidth)
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
        return rowCount * 58 + max(rowCount - 1, 0) * rowSpacing
    }

    private func columnCount(for width: CGFloat) -> Int {
        max(1, min(5, Int((width + 10) / (itemWidth + 10))))
    }

    private func itemSpacing(for width: CGFloat, columns: Int) -> CGFloat {
        guard columns > 1 else { return 0 }
        return max(10, (width - CGFloat(columns) * itemWidth) / CGFloat(columns - 1))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private struct GroupDetailSplitSheetPage: View {
    @State private var method = "Equally"

    private let members = ["Hong", "Lin", "Ming", "Yan"]

    var body: some View {
        Form {
            Section {
                Picker("Split method", selection: $method) {
                    Text("Equal").tag("Equally")
                    Text("Amount").tag("By amount")
                    Text("Shares").tag("Shares")
                }
                .pickerStyle(.segmented)
            }

            Section("Included") {
                ForEach(members, id: \.self) { member in
                    HStack {
                        Text(member)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GroupDetailTheme.accent)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .navigationTitle("Split")
        .navigationBarTitleDisplayMode(.inline)
        .tint(GroupDetailTheme.accent)
    }
}

private struct GroupDetailPaidBySheetPage: View {
    @Binding var selection: String

    private let members = ["Hong", "Lin", "Ming", "Yan"]

    var body: some View {
        List {
            ForEach(members, id: \.self) { member in
                Button {
                    selection = member
                } label: {
                    HStack {
                        Text(member)
                        Spacer()
                        if selection == member {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GroupDetailTheme.accent)
                        }
                    }
                }
                .foregroundStyle(GroupDetailTheme.ink)
                .listRowBackground(GroupDetailTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .navigationTitle("Paid by")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GroupDetailCategorySheetPage: View {
    @Binding var selection: String

    private let categories = ["Meal", "Hotel", "Transport", "Grocery", "Ticket", "Other"]

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                Button {
                    selection = category
                } label: {
                    HStack {
                        Text(category)
                        Spacer()
                        if selection == category {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GroupDetailTheme.accent)
                        }
                    }
                }
                .foregroundStyle(GroupDetailTheme.ink)
                .listRowBackground(GroupDetailTheme.formPaper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GroupDetailDateSheetPage: View {
    @Binding var selection: Date

    var body: some View {
        Form {
            DatePicker("Date", selection: $selection)
                .datePickerStyle(.graphical)
                .listRowBackground(GroupDetailTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(GroupDetailTheme.canvas)
        .navigationTitle("Date")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GroupDetailResolveTransfersButton: View {
    var body: some View {
        Button("Resolve 2 transfers") {
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityLabel("Resolve 2 transfers")
    }
}

private struct GroupDetailSummaryCard: View {
    let balance: String
    let memberInitials: [String]

    private var memberCountText: String {
        memberInitials.count == 1 ? "1 member" : "\(memberInitials.count) members"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("My balance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.secondaryInk)
                Text(balance)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GroupDetailTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            HStack(spacing: -8) {
                ForEach(memberInitials, id: \.self) { initial in
                    GroupDetailAvatar(initial: initial, size: 32)
                        .overlay {
                            Circle().stroke(GroupDetailTheme.paper, lineWidth: 2)
                        }
                }

                Text(memberCountText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.secondaryInk)
                    .padding(.leading, 14)

                Spacer()
            }
        }
        .padding(20)
        .groupDetailGlass(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(GroupDetailTheme.rule.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: GroupDetailTheme.ink.opacity(0.045), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("My balance \(balance). \(memberCountText).")
    }
}

private struct GroupDetailDebtSection: View {
    let debts: [GroupDetailMockDebt]
    let onShowDetails: () -> Void
    let onSelectDebt: (GroupDetailMockDebt) -> Void

    private var visibleDebts: [GroupDetailMockDebt] {
        Array(debts.prefix(3))
    }

    private var remainingCount: Int {
        max(debts.count - visibleDebts.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Balances")
                .font(.headline.weight(.semibold))
                .foregroundStyle(GroupDetailTheme.ink)

            VStack(spacing: 0) {
                ForEach(visibleDebts) { debt in
                    GroupDetailDebtRow(debt: debt) {
                        onSelectDebt(debt)
                    }
                    if debt.id != visibleDebts.last?.id {
                        Divider()
                            .overlay(GroupDetailTheme.rule.opacity(0.54))
                            .padding(.leading, 54)
                    }
                }

                Divider()
                    .overlay(GroupDetailTheme.rule.opacity(0.54))
                    .padding(.leading, 54)

                GroupDetailBalanceDetailsLinkRow(
                    remainingCount: remainingCount,
                    action: onShowDetails
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(GroupDetailTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GroupDetailTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
    }
}

private struct GroupDetailBalanceDetailsLinkRow: View {
    let remainingCount: Int
    let action: () -> Void

    private var title: String {
        remainingCount > 0 ? "View all" : "View details"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.accent)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.mutedInk.opacity(0.7))
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Opens balances as a sheet")
    }
}

private struct GroupDetailAllBalancesList: View {
    let debts: [GroupDetailMockDebt]
    let onSelectDebt: (GroupDetailMockDebt) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(debts) { debt in
                GroupDetailDebtRow(debt: debt) {
                    onSelectDebt(debt)
                }
                if debt.id != debts.last?.id {
                    Divider()
                        .overlay(GroupDetailTheme.rule.opacity(0.54))
                        .padding(.leading, 54)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(GroupDetailTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GroupDetailTheme.rule.opacity(0.62), lineWidth: 1)
        }
    }
}

private struct GroupDetailMemberBalancePlayground: View {
    @State private var editingRecord: GroupDetailMockRecord?

    let memberName: String

    private var debt: GroupDetailMockDebt {
        GroupDetailMockDebt.samples.first { $0.name == memberName } ?? GroupDetailMockDebt.samples[0]
    }

    private var records: [GroupDetailMockRecord] {
        GroupDetailMockRecord.records(relatedTo: memberName)
    }

    var body: some View {
        ZStack {
            GroupDetailTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupDetailMemberBalanceSummary(debt: debt)
                    GroupDetailMemberRecordSection(
                        memberName: memberName,
                        records: records
                    ) { record in
                        editingRecord = record
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(memberName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $editingRecord) { record in
            NavigationStack {
                GroupDetailNewExpenseSheet(mode: .edit(record))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct GroupDetailMemberBalanceSummary: View {
    let debt: GroupDetailMockDebt

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Balance with \(debt.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.secondaryInk)

                Text(debt.amount)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(debt.isPositive ? GroupDetailTheme.positive : GroupDetailTheme.negative)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()

            Text(debt.recordSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GroupDetailTheme.mutedInk)
        }
        .padding(18)
        .background(GroupDetailTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GroupDetailTheme.rule.opacity(0.62), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GroupDetailMemberRecordSection: View {
    let memberName: String
    let records: [GroupDetailMockRecord]
    let onEdit: (GroupDetailMockRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Records")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.ink)

                Spacer()

                Text("\(records.count) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.mutedInk)
            }

            VStack(spacing: 0) {
                ForEach(records) { record in
                    GroupDetailMemberRecordRow(
                        memberName: memberName,
                        record: record
                    ) {
                        onEdit(record)
                    }

                    if record.id != records.last?.id {
                        Divider()
                            .overlay(GroupDetailTheme.rule.opacity(0.52))
                            .padding(.leading, 48)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(GroupDetailTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GroupDetailTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
    }
}

private struct GroupDetailMemberRecordRow: View {
    let memberName: String
    let record: GroupDetailMockRecord
    let action: () -> Void

    private var meta: String {
        if record.payer == memberName {
            return "\(memberName) paid · \(record.participants) people"
        }

        return "\(record.payer) paid · \(memberName) included"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: record.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(record.color)
                    .frame(width: 30, height: 30)
                    .background(record.color.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GroupDetailTheme.ink)
                        .lineLimit(1)

                    Text(meta)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GroupDetailTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(record.amount)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(GroupDetailTheme.ink)

                    Text(record.time)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GroupDetailTheme.mutedInk)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.mutedInk.opacity(0.7))
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.title), \(record.amount), \(meta)")
        .accessibilityHint("Opens expense editor")
    }
}

private struct GroupDetailDebtRow: View {
    let debt: GroupDetailMockDebt
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GroupDetailAvatar(initial: debt.initial, size: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(debt.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GroupDetailTheme.ink)
                    Text(debt.recordSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GroupDetailTheme.secondaryInk)
                }

                Spacer()

                Text(debt.amount)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(debt.isPositive ? GroupDetailTheme.positive : GroupDetailTheme.negative)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.mutedInk.opacity(0.7))
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(debt.name), \(debt.direction), \(debt.amount), \(debt.recordSummary)")
        .accessibilityHint("Opens balance details")
    }
}

private struct GroupDetailSettlementPlanSection: View {
    private let transfers = [
        ("Yan", "pays", "Lin", "¥84.20"),
        ("Kai", "pays", "Ming", "¥18.00")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Suggested settlement")
                .font(.headline.weight(.semibold))
                .foregroundStyle(GroupDetailTheme.ink)

            VStack(spacing: 0) {
                ForEach(Array(transfers.enumerated()), id: \.offset) { index, transfer in
                    GroupDetailSettlementPlanRow(
                        payer: transfer.0,
                        action: transfer.1,
                        receiver: transfer.2,
                        amount: transfer.3
                    )

                    if index != transfers.count - 1 {
                        Divider()
                            .overlay(GroupDetailTheme.rule.opacity(0.54))
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(GroupDetailTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GroupDetailTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
    }
}

private struct GroupDetailSettlementPlanRow: View {
    let payer: String
    let action: String
    let receiver: String
    let amount: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(payer) \(action) \(receiver)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GroupDetailTheme.ink)

            Spacer()

            Text(amount)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(GroupDetailTheme.ink)
        }
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }
}

private struct GroupDetailRecordSection: View {
    let records: [GroupDetailMockRecord]
    let onEdit: (GroupDetailMockRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Expenses")
                .font(.headline.weight(.semibold))
                .foregroundStyle(GroupDetailTheme.ink)

            VStack(spacing: 0) {
                ForEach(records) { record in
                    GroupDetailRecordRow(record: record) {
                        onEdit(record)
                    }
                    if record.id != records.last?.id {
                        Divider()
                            .overlay(GroupDetailTheme.rule.opacity(0.56))
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(GroupDetailTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GroupDetailTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
    }
}

private struct GroupDetailRecordRow: View {
    let record: GroupDetailMockRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: record.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(record.color)
                    .frame(width: 38, height: 38)
                    .background(record.color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GroupDetailTheme.ink)
                    Text("\(record.payer) paid · \(record.participants) people")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GroupDetailTheme.secondaryInk)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(record.amount)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(GroupDetailTheme.ink)
                    Text(record.time)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GroupDetailTheme.mutedInk)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupDetailTheme.mutedInk.opacity(0.7))
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.title), \(record.amount), paid by \(record.payer)")
        .accessibilityHint("Opens expense details")
    }
}

private struct GroupDetailAvatar: View {
    let initial: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(GroupDetailTheme.canvas)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(GroupDetailTheme.secondaryInk)
            }
    }
}

private struct GroupDetailPreviewHost: View {
    var body: some View {
        NavigationStack {
            GroupDetailTheme.canvas
                .ignoresSafeArea()
                .navigationTitle("Groups")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(isPresented: .constant(true)) {
                    SoftLedgerGroupDetailPlayground()
                }
        }
    }
}

private struct GroupDetailMockDebt: Identifiable {
    let id = UUID()
    let initial: String
    let name: String
    let direction: String
    let amount: String
    let recordSummary: String
    let isPositive: Bool

    static let samples: [GroupDetailMockDebt] = [
        .init(initial: "L", name: "Lin", direction: "owes me", amount: "+¥128.40", recordSummary: "3 records", isPositive: true),
        .init(initial: "M", name: "Ming", direction: "owes me", amount: "+¥42.00", recordSummary: "1 record", isPositive: true),
        .init(initial: "Y", name: "Yan", direction: "I owe", amount: "-¥84.20", recordSummary: "2 records", isPositive: false),
        .init(initial: "A", name: "Ava", direction: "owes me", amount: "+¥24.80", recordSummary: "1 record", isPositive: true),
        .init(initial: "K", name: "Kai", direction: "I owe", amount: "-¥18.00", recordSummary: "1 record", isPositive: false)
    ]
}

private struct GroupDetailMockRecord: Identifiable {
    let id = UUID()
    let title: String
    let payer: String
    let amount: String
    let participants: Int
    let time: String
    let symbol: String
    let color: Color

    static let samples: [GroupDetailMockRecord] = [
        .init(title: "Hotel", payer: "Lin", amount: "¥420.00", participants: 4, time: "20:12", symbol: "bed.double.fill", color: GroupDetailTheme.accent),
        .init(title: "Dinner", payer: "Hong", amount: "¥186.00", participants: 3, time: "18:46", symbol: "fork.knife", color: Color(red: 0.188, green: 0.424, blue: 0.537)),
        .init(title: "Train tickets", payer: "Yan", amount: "¥252.60", participants: 4, time: "09:35", symbol: "ticket.fill", color: GroupDetailTheme.positive)
    ]

    static func records(relatedTo memberName: String) -> [GroupDetailMockRecord] {
        switch memberName {
        case "Lin":
            [
                .init(title: "Hotel", payer: "Lin", amount: "¥420.00", participants: 4, time: "20:12", symbol: "bed.double.fill", color: GroupDetailTheme.accent),
                .init(title: "Dinner", payer: "Hong", amount: "¥186.00", participants: 3, time: "18:46", symbol: "fork.knife", color: Color(red: 0.188, green: 0.424, blue: 0.537)),
                .init(title: "Coffee", payer: "Lin", amount: "¥36.40", participants: 2, time: "Yesterday", symbol: "cup.and.saucer.fill", color: Color(red: 0.522, green: 0.384, blue: 0.250))
            ]
        case "Ming":
            [
                .init(title: "Dinner", payer: "Hong", amount: "¥186.00", participants: 3, time: "18:46", symbol: "fork.knife", color: Color(red: 0.188, green: 0.424, blue: 0.537))
            ]
        case "Yan":
            [
                .init(title: "Train tickets", payer: "Yan", amount: "¥252.60", participants: 4, time: "09:35", symbol: "ticket.fill", color: GroupDetailTheme.positive),
                .init(title: "Taxi", payer: "Hong", amount: "¥48.00", participants: 2, time: "Yesterday", symbol: "car.fill", color: Color(red: 0.290, green: 0.565, blue: 0.690))
            ]
        case "Ava":
            [
                .init(title: "Groceries", payer: "Ava", amount: "¥78.80", participants: 4, time: "May 8", symbol: "cart.fill", color: Color(red: 0.314, green: 0.470, blue: 0.760))
            ]
        case "Kai":
            [
                .init(title: "Tickets", payer: "Hong", amount: "¥54.00", participants: 3, time: "May 8", symbol: "ticket.fill", color: Color(red: 0.612, green: 0.424, blue: 0.729))
            ]
        default:
            samples
        }
    }
}

private struct GroupDetailExpenseCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let color: Color

    static let samples: [GroupDetailExpenseCategory] = [
        .init(id: "meal", title: "Meal", symbol: "fork.knife", color: Color(red: 0.188, green: 0.424, blue: 0.537)),
        .init(id: "drink", title: "Drink", symbol: "cup.and.saucer.fill", color: Color(red: 0.522, green: 0.384, blue: 0.250)),
        .init(id: "hotel", title: "Hotel", symbol: "bed.double.fill", color: GroupDetailTheme.accent),
        .init(id: "shopping", title: "Shopping", symbol: "cart.fill", color: Color(red: 0.314, green: 0.470, blue: 0.760)),
        .init(id: "transport", title: "Transport", symbol: "tram.fill", color: GroupDetailTheme.positive),
        .init(id: "stay", title: "Stay", symbol: "house.fill", color: Color(red: 0.376, green: 0.570, blue: 0.494)),
        .init(id: "vacation", title: "Vacation", symbol: "beach.umbrella.fill", color: Color(red: 0.290, green: 0.565, blue: 0.690)),
        .init(id: "transfer", title: "Transfer", symbol: "banknote.fill", color: Color(red: 0.620, green: 0.514, blue: 0.218)),
        .init(id: "ticket", title: "Ticket", symbol: "ticket.fill", color: Color(red: 0.612, green: 0.424, blue: 0.729)),
        .init(id: "game", title: "Game", symbol: "dice.fill", color: Color(red: 0.553, green: 0.455, blue: 0.742)),
        .init(id: "other", title: "Other", symbol: "ellipsis", color: GroupDetailTheme.mutedInk)
    ]
}

private enum GroupDetailTheme {
    static let canvas = adaptive(light: 0xF6F2EA, dark: 0x131416)
    static let paper = adaptive(light: 0xFEFCF6, dark: 0x1D1E20)
    static let formPaper = adaptive(light: 0xFFFDF8, dark: 0x222326)
    static let ink = adaptive(light: 0x25221D, dark: 0xF1F0EC)
    static let secondaryInk = adaptive(light: 0x746C5D, dark: 0xC7C4BE)
    static let mutedInk = adaptive(light: 0x9D917E, dark: 0x92918C)
    static let rule = adaptive(light: 0xDAD2C0, dark: 0x34363A)
    static let positive = adaptive(light: 0x167454, dark: 0x77C99E)
    static let negative = adaptive(light: 0xAC2F24, dark: 0xF07C6C)
    static let accent = adaptive(light: 0xB15525, dark: 0xE49B63)
}

private struct GroupDetailGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if interactive {
            content
                .glassEffect(.regular.tint(GroupDetailTheme.paper.opacity(0.32)).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .glassEffect(.regular.tint(GroupDetailTheme.paper.opacity(0.26)), in: .rect(cornerRadius: cornerRadius))
        }
    }
}

private struct GroupDetailCircleGlassModifier: ViewModifier {
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if interactive {
            content
                .glassEffect(.regular.tint(GroupDetailTheme.paper.opacity(0.30)).interactive(), in: Circle())
        } else {
            content
                .glassEffect(.regular.tint(GroupDetailTheme.paper.opacity(0.24)), in: Circle())
        }
    }
}

private extension View {
    func groupDetailGlass(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(GroupDetailGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    func groupDetailCircleGlass(interactive: Bool = false) -> some View {
        modifier(GroupDetailCircleGlassModifier(interactive: interactive))
    }
}

private func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { traitCollection in
        UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
    })
}

#Preview("Group detail UX") {
    GroupDetailPreviewHost()
}

#Preview("Group detail empty") {
    NavigationStack {
        SoftLedgerGroupDetailPlayground(scenario: .peopleSetupEmpty)
    }
}
