#if DEBUG
import SwiftUI

/// Uses production screens with fixture data; never requests remote ledger data.
struct MemberDetailsPlayground: View {
    enum Screen { case group, members, member, yourself, editor }

    @StateObject private var store: WalkcalcStore
    let screen: Screen

    init(screen: Screen = .members, edgeCases: Bool = false) {
        self.screen = screen
        let store = WalkcalcStore()
        store.applyDebugFixture(.appStore)
        // Initials keep the preview independent of avatar image servers.
        for index in store.groups.indices {
            for memberIndex in store.groups[index].membersInfo.indices {
                store.groups[index].membersInfo[memberIndex].avatar = ""
            }
        }
        if let group = store.groups.first, let receiver = group.allMembers.first {
            store.setPreviewSettlementSuggestions(group.allMembers.dropFirst().map { member in
                SettlementTransfer(fromId: member.uuid, toId: receiver.uuid,
                                   amountMinor: Money.absolute(member.debtMinor), currencyCode: group.currencyCode)
            }, groupId: group.id)
        }
        if edgeCases {
            Self.applyEdgeCases(to: store)
        }
        _store = StateObject(wrappedValue: store)
    }

    private static func applyEdgeCases(to store: WalkcalcStore) {
        store.groups[0].name = "Payment layout · edge cases"
        store.groups[0].membersInfo[1].name = "Alexandra Catherine Montgomery-Wellington"
        store.groups[0].membersInfo[2].name = "Christopher Benjamin Alexander-Richardson"
        store.groups[0].membersInfo[3].name = "李小明这是一位拥有非常长显示名称的成员"
        store.groups[0].membersInfo.append(Member(uuid: "preview-alex", name: "Alex", avatar: "", debtMinor: "0", costMinor: "0"))
        let group = store.groups[0]
        let ids = group.allMembers.map(\.uuid)
        store.setPreviewSettlementSuggestions([
            SettlementTransfer(fromId: ids[1], toId: ids[0], amountMinor: "123456789", currencyCode: "USD"),
            SettlementTransfer(fromId: ids[0], toId: ids[2], amountMinor: "23456", currencyCode: "USD"),
            SettlementTransfer(fromId: ids[1], toId: ids[2], amountMinor: "12345", currencyCode: "USD"),
            SettlementTransfer(fromId: ids[3], toId: ids[0], amountMinor: "6789", currencyCode: "CNY"),
            SettlementTransfer(fromId: ids[4], toId: ids[0], amountMinor: "1234", currencyCode: "USD")
        ], groupId: group.id)
        let cases: [(String, Int, [Int], Bool)] = [
            ("2 people · you first", 4, [2, 0], false),
            ("3 people · summary", 4, [1, 0, 2], false),
            ("All members · everyone", 4, [1, 2, 3, 4, 0], false),
            ("You paid for yourself", 0, [0], false),
            ("You paid for two others", 0, [4, 1], false),
            ("You and another person", 0, [4, 0], false),
            ("Alex paid for themselves", 4, [4, 0], false),
            ("Long payer and recipient", 1, [2, 3], false),
            ("Settlement · paid to you", 4, [0], true)
        ]
        let now = Date().timeIntervalSince1970 * 1000
        store.recordsByGroup[group.id] = cases.enumerated().map { index, item in
            WalkRecord(recordId: "participant-edge-\(index)", who: ids[item.1], paidMinor: "1234",
                       forWhom: item.2.map { ids[$0] }, type: "food", text: item.0, long: "", lat: "",
                       createdAt: now, occurredAt: now - Double(index) * 60_000, modifiedAt: now,
                       isDebtResolve: item.3, currencyCode: "USD")
        }
        store.recordTotals[group.id] = cases.count
        for index in store.groups[0].membersInfo.indices {
            let id = store.groups[0].membersInfo[index].uuid
            store.groups[0].membersInfo[index].recordCount = (store.recordsByGroup[group.id] ?? []).filter {
                $0.who == id || $0.forWhom.contains(id)
            }.count
        }
    }

    var body: some View {
        if let group = store.groups.first {
            Group {
                if screen == .group {
                    NavigationStack { GroupView(groupId: group.id) }
                } else if screen == .editor {
                    NavigationStack {
                        RecordEditorView(groupId: group.id, record: store.recordsByGroup[group.id]?.first) {}
                    }
                } else {
                    BalancesWorkspace(
                        group: group,
                        initialMember: screen == .members ? nil : group.allMembers[screen == .yourself ? 0 : 1],
                        showsRoot: screen == .members
                    )
                }
            }
            .environmentObject(store)
        }
    }
}

#Preview("成员明细 · 真实组件") { MemberDetailsPlayground() }
#Preview("成员账单 · 真实组件") { MemberDetailsPlayground(screen: .member) }
#Preview("自己的账单 · 真实组件") { MemberDetailsPlayground(screen: .yourself) }
#Preview("群组结清入口 · 真实组件") { MemberDetailsPlayground(screen: .group) }
#Preview("超长姓名与多人账单") { MemberDetailsPlayground(edgeCases: true) }
#Preview("账单编辑 · 间距") { MemberDetailsPlayground(screen: .editor) }
#endif
