import SwiftUI

enum GroupSheet: Identifiable {
    case addRecord
    case editRecord(WalkRecord)
    case share
    case debtDetail
    case recordDetail(WalkRecord)
    case settings
    case addMember

    var id: String {
        switch self {
        case .addRecord: "addRecord"
        case .editRecord(let record): "editRecord-\(record.recordId)"
        case .share: "share"
        case .debtDetail: "debtDetail"
        case .recordDetail(let record): "recordDetail-\(record.recordId)"
        case .settings: "settings"
        case .addMember: "addMember"
        }
    }
}

struct GroupView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss
    var groupId: String
    @State private var activeSheet: GroupSheet?
    @State private var confirmDismiss = false

    var group: WalkGroup? {
        store.group(id: groupId)
    }

    var records: [WalkRecord] {
        store.recordsByGroup[groupId] ?? []
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let group {
                        GroupTopCard(
                            group: group,
                            onShare: { activeSheet = .share },
                            onDebtDetail: { activeSheet = .debtDetail },
                            onAddMember: { activeSheet = .addMember }
                        )
                        .padding(.bottom, 4)
                    } else {
                        ProgressView()
                    }
                    ForEach(sectionedRecords(), id: \.record.recordId) { item in
                        if item.isSectionHead {
                            Text(DateFormatter.walkDate.string(from: item.record.modifiedAt.walkDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 8)
                        }
                        Button {
                            activeSheet = .recordDetail(item.record)
                        } label: {
                            RecordCard(record: item.record, group: group)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if item.record == records.last {
                                Task { await store.loadMoreRecords(groupId: groupId) }
                            }
                        }
                    }
                    if let total = store.recordTotals[groupId], total <= records.count, !records.isEmpty {
                        Text("- \(L("The End")) -")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
                .padding(20)
                .padding(.bottom, 88)
            }
            .refreshable { await store.refreshGroup(groupId) }

            Button {
                activeSheet = .addRecord
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(store.primaryColor, in: Circle())
                    .shadow(radius: 8, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 30)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L("Group")).font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task { await store.refreshGroup(groupId) }
        .sheet(item: $activeSheet) { sheet in
            GroupSheetView(groupId: groupId, sheet: sheet, activeSheet: $activeSheet, dismissGroup: {
                dismiss()
            })
        }
    }

    private func sectionedRecords() -> [(record: WalkRecord, isSectionHead: Bool)] {
        var lastDay: Int?
        return records.map { record in
            let day = Calendar.current.ordinality(of: .day, in: .era, for: record.createdAt.walkDate) ?? 0
            let isHead = day != lastDay
            lastDay = day
            return (record, isHead)
        }
    }
}

struct GroupTopCard: View {
    @EnvironmentObject private var store: WalkcalcStore
    var group: WalkGroup
    var onShare: () -> Void
    var onDebtDetail: () -> Void
    var onAddMember: () -> Void

    var myDebt: MoneyMinor {
        group.membersInfo.first(where: { $0.uuid == store.user?.uuid })?.debtMinor ?? "0"
    }

    var body: some View {
        CardContainer {
            VStack(spacing: 20) {
                HStack {
                    Text(group.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                    Spacer()
                    if group.isOwner {
                        Image(systemName: "crown.fill").foregroundStyle(.yellow)
                    }
                    Button(action: onShare) {
                        Image(systemName: "qrcode")
                    }
                }
                Button(action: onAddMember) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Members"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: -8) {
                            ForEach(Array(group.allMembers.prefix(4))) { member in
                                AvatarView(member: member, size: 28)
                                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                            }
                            if group.allMembers.count < 4 {
                                Image(systemName: "plus.circle.fill")
                                    .padding(.leading, 14)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                HStack {
                    Button(action: onDebtDetail) {
                        Label(L("Debt detail"), systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    Spacer()
                    StackText(
                        top: Money.isNegative(myDebt) ? L("I owed") : L("Owed to me"),
                        bottom: "\(Money.isNegative(myDebt) ? "" : "+")\(Money.display(myDebt))",
                        alignment: .trailing
                    )
                }
            }
        }
    }
}

struct RecordCard: View {
    @EnvironmentObject private var store: WalkcalcStore
    var record: WalkRecord
    var group: WalkGroup?

    var payer: Member? {
        group?.allMembers.first(where: { $0.uuid == record.who })
    }

    var body: some View {
        CardContainer {
            HStack {
                VStack(spacing: 2) {
                    Text(categoryEmoji[record.type] ?? "🍎")
                        .font(.title2)
                    Label("\(record.forWhom.count)", systemImage: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 34).padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 6) {
                    Text(payer?.name ?? "")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5), in: Capsule())
                    Text(record.createdAt.walkDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Money.display(record.paidMinor))
                        .font(.headline)
                    if record.isDebtResolve {
                        Text(L("Debt Resolve"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !record.text.isEmpty {
                        Text(record.text)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(L("My part")): \(myPart)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var myPart: String {
        guard record.forWhom.contains(store.user?.uuid ?? "") else { return "0.00" }
        return Money.display(Money.splitFirst(record.paidMinor, count: record.forWhom.count))
    }
}

struct GroupSheetView: View {
    @EnvironmentObject private var store: WalkcalcStore
    var groupId: String
    var sheet: GroupSheet
    @Binding var activeSheet: GroupSheet?
    var dismissGroup: () -> Void

    var group: WalkGroup? { store.group(id: groupId) }

    var body: some View {
        NavigationStack {
            Group {
                switch sheet {
                case .addRecord:
                    RecordEditorView(groupId: groupId) {
                        activeSheet = nil
                    }
                case .editRecord(let record):
                    RecordEditorView(groupId: groupId, record: record) {
                        activeSheet = nil
                    }
                case .share:
                    ShareGroupView(groupId: groupId)
                case .debtDetail:
                    if let group {
                        DebtDetailView(group: group)
                    }
                case .recordDetail(let record):
                    RecordDetailView(record: record, group: group, onEdit: {
                        activeSheet = .editRecord(record)
                    }, onDelete: {
                        Task {
                            if await store.deleteRecord(groupId: groupId, recordId: record.recordId) {
                                activeSheet = nil
                            }
                        }
                    })
                case .settings:
                    if let group {
                        GroupSettingsPanel(group: group, recordCount: store.recordTotals[groupId] ?? 0, onDismiss: {
                            Task {
                                if await store.deleteGroup(groupId) {
                                    activeSheet = nil
                                    dismissGroup()
                                }
                            }
                        })
                    }
                case .addMember:
                    if let group {
                        AddMemberView(group: group) {
                            activeSheet = nil
                        }
                    }
                }
            }
            .padding(20)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { activeSheet = nil }
                }
            }
        }
        .presentationDetents(presentationDetents)
    }

    private var title: String {
        switch sheet {
        case .addRecord: L("Add record")
        case .editRecord: L("Edit record")
        case .share: L("Share")
        case .debtDetail: L("Debt detail")
        case .recordDetail: L("Record detail")
        case .settings: L("Group setting")
        case .addMember: L("Add member")
        }
    }

    private var presentationDetents: Set<PresentationDetent> {
        switch sheet {
        case .addRecord, .editRecord:
            return [.large]
        default:
            return [.medium, .large]
        }
    }
}
