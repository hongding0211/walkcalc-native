#if DEBUG
import Foundation

enum WalkcalcDebugFixture: String {
    case empty = "--ui-fixture-empty"
    case peopleSetup = "--ui-fixture-people-empty"
    case emptyBalance = "--ui-fixture-empty-balance"
    case stress = "--ui-fixture-stress"
    case edge = "--ui-fixture-edge"

    static var current: WalkcalcDebugFixture? {
        ProcessInfo.processInfo.arguments.compactMap(WalkcalcDebugFixture.init(rawValue:)).first
    }
}

@MainActor
extension WalkcalcStore {
    func applyDebugFixture(_ fixture: WalkcalcDebugFixture) {
        isFixtureMode = true
        isBootstrapping = false
        token = "debug-fixture-token"
        user = UserProfile(uuid: "fixture-current-user", name: "Hong", avatar: "")
        errorMessage = nil
        recordsByGroup = [:]
        recordTotals = [:]

        switch fixture {
        case .empty:
            groups = []
        case .peopleSetup:
            groups = [fixtureGroup(id: "people-empty", name: "New group", members: [fixtureMember("fixture-current-user", "Hong")], tempUsers: [])]
            recordsByGroup["people-empty"] = []
            recordTotals["people-empty"] = 0
        case .emptyBalance:
            groups = [fixtureGroup(id: "empty-balance", name: "23213213", members: [
                fixtureMember("fixture-current-user", "Hong"),
                fixtureMember("empty-balance-member", "123")
            ], tempUsers: [])]
            recordsByGroup["empty-balance"] = []
            recordTotals["empty-balance"] = 0
        case .stress:
            applyStressFixture()
        case .edge:
            applyEdgeFixture()
        }
        totalBalanceMinor = totalDebtMinor()
    }

    private func applyStressFixture() {
        let memberNames = ["Hong", "Alexandra", "Christopher", "Lin", "Ming", "Yan", "Noah", "Ivy", "Owen", "Tara", "June", "Keith"]
        let members = memberNames.enumerated().map { index, name in
            fixtureMember(index == 0 ? "fixture-current-user" : "member-\(index)", name)
        }
        groups = (0..<90).map { index in
            var group = fixtureGroup(
                id: "stress-\(index)",
                name: index == 0 ? "Stress Search Base Group" : "Stress Group \(String(format: "%02d", index))",
                members: members,
                tempUsers: []
            )
            group.membersInfo[0].debtMinor = index.isMultiple(of: 2) ? "\(index * 137)" : "-\(index * 83)"
            return group
        }

        var records: [WalkRecord] = []
        records.reserveCapacity(180)

        for index in 0..<180 {
            let member = members[index % members.count]
            let participantIds = Array(members.prefix((index % members.count) + 1).map(\.uuid))
            let categoryId = expenseCategories[index % expenseCategories.count].id
            let note = index.isMultiple(of: 9) ? "Needle search item \(index)" : ""
            let timestamp = Date().addingTimeInterval(TimeInterval(-index * 120)).timeIntervalSince1970 * 1000

            records.append(WalkRecord(
                recordId: "stress-record-\(index)",
                who: member.uuid,
                paidMinor: "\((index + 1) * 123)",
                forWhom: participantIds,
                type: categoryId,
                text: note,
                long: "",
                lat: "",
                createdAt: timestamp,
                occurredAt: timestamp,
                modifiedAt: timestamp,
                isDebtResolve: false
            ))
        }

        recordsByGroup["stress-0"] = records
        recordTotals["stress-0"] = records.count
    }

    private func applyEdgeFixture() {
        let longName = "Very Long Mixed 中文 English Group Name For Layout Stress 2026"
        var group = fixtureGroup(
            id: "edge-main",
            name: longName,
            members: [
                fixtureMember("fixture-current-user", "Hong"),
                fixtureMember("edge-member-1", "Alexandra Christopher-Lin 中文长名"),
                fixtureMember("edge-member-2", "Yan"),
                fixtureMember("edge-member-3", "Ming")
            ],
            tempUsers: [
                fixtureMember("edge-temp-1", "Temporary member with long name", isTemporary: true)
            ]
        )
        group.membersInfo[0].debtMinor = "123456789012"
        group.membersInfo[1].debtMinor = "-98765432100"
        group.membersInfo[2].debtMinor = "0"
        groups = [group]
        recordsByGroup[group.id] = [
            WalkRecord(
                recordId: "edge-record-1",
                who: "edge-member-1",
                paidMinor: "123456789012",
                forWhom: group.allMembers.map(\.uuid),
                type: "accommodation",
                text: "A very long optional note that should truncate in rows but stay searchable 中文 English",
                long: "",
                lat: "",
                createdAt: Date().timeIntervalSince1970 * 1000,
                occurredAt: Date().timeIntervalSince1970 * 1000,
                modifiedAt: Date().timeIntervalSince1970 * 1000,
                isDebtResolve: false
            ),
            WalkRecord(
                recordId: "edge-record-2",
                who: "fixture-current-user",
                paidMinor: "1",
                forWhom: ["fixture-current-user"],
                type: "other",
                text: "",
                long: "",
                lat: "",
                createdAt: Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000,
                occurredAt: Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000,
                modifiedAt: Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000,
                isDebtResolve: false
            ),
            WalkRecord(
                recordId: "edge-record-3",
                who: "edge-member-2",
                paidMinor: "987654",
                forWhom: ["edge-member-2", "edge-member-3"],
                type: "food",
                text: "",
                long: "",
                lat: "",
                createdAt: Date().addingTimeInterval(-7200).timeIntervalSince1970 * 1000,
                occurredAt: Date().addingTimeInterval(-7200).timeIntervalSince1970 * 1000,
                modifiedAt: Date().addingTimeInterval(-7200).timeIntervalSince1970 * 1000,
                isDebtResolve: false
            )
        ]
        recordTotals[group.id] = recordsByGroup[group.id]?.count ?? 0
    }

    private func fixtureGroup(id: String, name: String, members: [Member], tempUsers: [Member]) -> WalkGroup {
        WalkGroup(
            id: id,
            name: name,
            createdAt: Date().timeIntervalSince1970 * 1000,
            modifiedAt: Date().timeIntervalSince1970 * 1000,
            membersInfo: members,
            tempUsers: tempUsers,
            archivedUsers: [],
            isOwner: true
        )
    }

    private func fixtureMember(_ uuid: String, _ name: String, isTemporary: Bool = false) -> Member {
        Member(uuid: uuid, name: name, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: isTemporary)
    }
}
#endif
