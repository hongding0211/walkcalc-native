import SwiftUI

enum GroupSheet: Identifiable {
    case newExpense
    case editExpense(WalkRecord)
    case groupSettings
    case balances(Member?)
    case peopleSetup

    var id: String {
        switch self {
        case .newExpense: "newExpense"
        case .editExpense(let record): "editExpense-\(record.recordId)"
        case .groupSettings: "groupSettings"
        case .balances(let member): "balances-\(member?.id ?? "root")"
        case .peopleSetup: "peopleSetup"
        }
    }
}

struct GroupView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let groupId: String
    @State private var activeSheet: GroupSheet?
    @State private var searchText = ""

    private var group: WalkGroup? {
        store.group(id: groupId)
    }

    private var records: [WalkRecord] {
        let source = store.recordsByGroup[groupId] ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { record in
            recordTitle(record).localizedCaseInsensitiveContains(query)
                || Money.display(record.paidMinor).contains(query)
        }
    }

    private var shouldShowPeopleSetup: Bool {
        guard let group else { return false }
        return group.allMembers.count == 1 && records.isEmpty
    }

    var body: some View {
        ZStack {
            SoftLedgerBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let group {
                        if shouldShowPeopleSetup {
                            PeopleSetupEmptyState {
                                activeSheet = .peopleSetup
                            }
                        } else {
                            GroupSummaryCard(group: group)
                            GroupBalancesSection(group: group) { selectedMember in
                                activeSheet = .balances(selectedMember)
                            }
                            GroupExpensesSection(group: group, records: records) { record in
                                activeSheet = .editExpense(record)
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(L("Loading groups..."))
                                .font(.callout)
                                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
            .refreshable { await store.refreshGroup(groupId) }
        }
        .navigationTitle(group?.name ?? L("Group"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .groupSettings
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(L("Group settings"))
            }

            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    activeSheet = .newExpense
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(L("Add expense"))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: L("Search"))
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await store.refreshGroup(groupId) }
        .sheet(item: $activeSheet) { sheet in
            GroupSheetView(groupId: groupId, sheet: sheet, activeSheet: $activeSheet) {
                dismiss()
            }
        }
    }
}

private struct GroupSummaryCard: View {
    @EnvironmentObject private var store: WalkcalcStore
    let group: WalkGroup

    private var myBalance: MoneyMinor {
        group.membersInfo.first(where: { $0.uuid == store.user?.uuid })?.debtMinor ?? "0"
    }

    var body: some View {
        SoftLedgerCard(usesGlass: true) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("My balance"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    Text(signedMoney(myBalance))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                HStack(spacing: -8) {
                    SoftLedgerAvatarStack(members: group.allMembers, visibleCount: 4, size: 32, showsTotal: false)
                        .accessibilityHidden(true)
                    Text(L("%@ members").replacingOccurrences(of: "%@", with: "\(group.allMembers.count)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .padding(.leading, 14)
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GroupBalancesSection: View {
    @EnvironmentObject private var store: WalkcalcStore
    let group: WalkGroup
    let onSelect: (Member?) -> Void

    private var currentUserId: String {
        store.user?.uuid ?? ""
    }

    private var balances: [Member] {
        group.allMembers.filter { $0.uuid != currentUserId }
    }

    private var visibleBalances: [Member] {
        Array(balances.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("Balances"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)

            VStack(spacing: 0) {
                if visibleBalances.isEmpty {
                    Text(L("No balances"))
                        .font(.subheadline)
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                } else {
                    ForEach(visibleBalances) { member in
                        BalancePreviewRow(member: member, recordCount: recordCount(for: member)) {
                            onSelect(member)
                        }
                        if member.id != visibleBalances.last?.id {
                            Divider()
                                .overlay(SoftLedgerTheme.rule.opacity(0.54))
                                .padding(.leading, 54)
                        }
                    }

                    Divider()
                        .overlay(SoftLedgerTheme.rule.opacity(0.54))
                        .padding(.leading, 54)

                    Button {
                        onSelect(nil)
                    } label: {
                        HStack(spacing: 8) {
                            Text(balances.count > 3 ? L("View all") : L("View details"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
    }

    private func recordCount(for member: Member) -> Int {
        (store.recordsByGroup[group.id] ?? []).filter { record in
            record.who == member.uuid || record.forWhom.contains(member.uuid)
        }.count
    }
}

struct BalancePreviewRow: View {
    let member: Member
    let recordCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SoftLedgerAvatar(member: member, size: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                    Text(L("%@ records").replacingOccurrences(of: "%@", with: "\(recordCount)"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                }

                Spacer()

                Text(signedMoney(member.debtMinor))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(moneyColor(member.debtMinor))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct GroupExpensesSection: View {
    let group: WalkGroup
    let records: [WalkRecord]
    let onEdit: (WalkRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Expenses"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)

            VStack(spacing: 0) {
                if records.isEmpty {
                    Text(L("No expenses yet"))
                        .font(.subheadline)
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                } else {
                    ForEach(records) { record in
                        ExpenseRow(record: record, group: group) {
                            onEdit(record)
                        }
                        if record.id != records.last?.id {
                            Divider()
                                .overlay(SoftLedgerTheme.rule.opacity(0.56))
                                .padding(.leading, 54)
                        }
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
        }
    }
}

struct ExpenseRow: View {
    let record: WalkRecord
    let group: WalkGroup
    let action: () -> Void

    private var payer: Member? {
        group.allMembers.first(where: { $0.uuid == record.who })
    }

    private var category: ExpenseCategory {
        expenseCategory(for: record.type)
    }

    private var payerName: String {
        payer?.name ?? L("Unknown")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(category.color)
                    .frame(width: 38, height: 38)
                    .background(category.color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(recordTitle(record))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        Text(payerName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Text(" \(L("paid for")) \(record.forWhom.count)")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
                }
                .layoutPriority(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("¥\(Money.compactDisplay(record.paidMinor))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .frame(minWidth: 70, alignment: .trailing)
                    Text(record.createdAt.walkDate, style: .time)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.mutedInk)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(recordTitle(record)), \(payerName) \(L("paid for")) \(record.forWhom.count), ¥\(Money.compactDisplay(record.paidMinor)), \(record.createdAt.walkDate.formatted(date: .omitted, time: .shortened))")
    }
}

private struct PeopleSetupEmptyState: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SoftLedgerTheme.accent)
                .frame(width: 64, height: 64)
                .background(SoftLedgerTheme.paper, in: Circle())
                .overlay {
                    Circle().stroke(SoftLedgerTheme.rule.opacity(0.65), lineWidth: 1)
                }

            VStack(spacing: 6) {
                Text(L("Add people"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.ink)

                Text(L("Add members or temporary members when this becomes a shared expense group."))
                    .font(.callout)
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                action()
            } label: {
                Label(L("Add people"), systemImage: "person.badge.plus")
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}
