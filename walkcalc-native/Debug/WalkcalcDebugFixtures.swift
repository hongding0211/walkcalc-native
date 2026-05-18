#if DEBUG
import Foundation

enum WalkcalcDebugFixture: String {
    case empty = "--ui-fixture-empty"
    case peopleSetup = "--ui-fixture-people-empty"
    case emptyBalance = "--ui-fixture-empty-balance"
    case stress = "--ui-fixture-stress"
    case edge = "--ui-fixture-edge"
    case appStore = "--ui-fixture-appstore"

    static var current: WalkcalcDebugFixture? {
        ProcessInfo.processInfo.arguments.compactMap(WalkcalcDebugFixture.init(rawValue:)).first
    }
}

@MainActor
extension WalkcalcStore {
    func applyAuthSessionSimulationSeedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--simulate-auth-session-seed") else {
            return
        }

        let environment = ProcessInfo.processInfo.environment
        guard let accessToken = environment["WALKCALC_SIM_ACCESS_TOKEN"],
              let refreshToken = environment["WALKCALC_SIM_REFRESH_TOKEN"],
              !accessToken.isEmpty,
              !refreshToken.isEmpty,
              let apiHost = api.baseURL.host else {
            print("AUTH_SIM seed skipped: missing WALKCALC_SIM_ACCESS_TOKEN or WALKCALC_SIM_REFRESH_TOKEN")
            return
        }

        NativeAuthSession.clearAuthCookies(baseURL: api.baseURL, webBaseURL: api.webBaseURL)
        let expiresDate = Date().addingTimeInterval(60 * 30)
        let refreshCookie = HTTPCookie(properties: [
            .domain: apiHost,
            .path: "/",
            .name: NativeAuthSession.refreshCookieName,
            .value: refreshToken,
            .expires: expiresDate,
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ])

        if let refreshCookie {
            _ = NativeAuthSession.importAuthCookies([refreshCookie], baseURL: api.baseURL, webBaseURL: api.webBaseURL)
        }

        token = accessToken
        user = nil
        finishStartup(.resolving)
        isBootstrapping = true
        UserDefaults.standard.set(accessToken, forKey: "walkcalc.token")
        print("AUTH_SIM seeded accessToken and refreshCookie for \(api.baseURL.absoluteString)")
    }

    func applyDebugFixture(_ fixture: WalkcalcDebugFixture) {
        isFixtureMode = true
        finishStartup(.authenticated)
        token = "debug-fixture-token"
        user = UserProfile(uuid: "fixture-current-user", name: "Hong", avatar: "")
        urgentAlert = nil
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
        case .appStore:
            applyAppStoreFixture()
        }
        totalBalanceMinor = totalDebtMinor()
    }

    private func applyAppStoreFixture() {
        var tokyo = fixtureGroup(
            id: "appstore-tokyo",
            name: "Weekend in Tokyo",
            members: [
                fixtureMember("fixture-current-user", "Hong", debtMinor: "4320", costMinor: "18840", recordCount: 4),
                fixtureMember("appstore-ava", "Ava", debtMinor: "-2160", costMinor: "12480", recordCount: 3),
                fixtureMember("appstore-noah", "Noah", debtMinor: "-1260", costMinor: "9360", recordCount: 3),
                fixtureMember("appstore-mia", "Mia", debtMinor: "-900", costMinor: "8160", recordCount: 2)
            ],
            tempUsers: []
        )
        tokyo.hasCurrentUserBalanceSummary = true
        tokyo.currentUserBalanceMinor = "4320"
        tokyo.currentUserExpenseShareMinor = "18840"
        tokyo.currentUserPaidTotalMinor = "23160"
        tokyo.currentUserRecordCount = 4
        tokyo.participantCount = tokyo.allMembers.count
        tokyo.participantPreview = Array(tokyo.allMembers.prefix(4))
        tokyo.serverHasUnresolvedBalance = true

        var apartment = fixtureGroup(
            id: "appstore-apartment",
            name: "Apartment Essentials",
            members: [
                fixtureMember("fixture-current-user", "Hong", debtMinor: "-1850", costMinor: "7340", recordCount: 2),
                fixtureMember("appstore-lina", "Lina", debtMinor: "1850", costMinor: "9190", recordCount: 2)
            ],
            tempUsers: []
        )
        apartment.hasCurrentUserBalanceSummary = true
        apartment.currentUserBalanceMinor = "-1850"
        apartment.currentUserExpenseShareMinor = "7340"
        apartment.currentUserPaidTotalMinor = "5490"
        apartment.currentUserRecordCount = 2
        apartment.participantCount = apartment.allMembers.count
        apartment.participantPreview = apartment.allMembers
        apartment.serverHasUnresolvedBalance = true

        groups = [tokyo, apartment]

        let now = Date().timeIntervalSince1970 * 1000
        recordsByGroup[tokyo.id] = [
            fixtureRecord(
                id: "appstore-record-1",
                payer: "fixture-current-user",
                amountMinor: "12800",
                participants: tokyo.allMembers.map(\.uuid),
                category: "food",
                note: "Dinner in Shibuya",
                offsetHours: 0,
                now: now
            ),
            fixtureRecord(
                id: "appstore-record-2",
                payer: "appstore-ava",
                amountMinor: "24600",
                participants: tokyo.allMembers.map(\.uuid),
                category: "accommodation",
                note: "Hotel for two nights",
                offsetHours: 5,
                now: now
            ),
            fixtureRecord(
                id: "appstore-record-3",
                payer: "appstore-noah",
                amountMinor: "4800",
                participants: ["fixture-current-user", "appstore-ava", "appstore-noah"],
                category: "traffic",
                note: "Airport train tickets",
                offsetHours: 9,
                now: now
            ),
            fixtureRecord(
                id: "appstore-record-4",
                payer: "fixture-current-user",
                amountMinor: "3600",
                participants: ["fixture-current-user", "appstore-mia"],
                category: "beverage",
                note: "Morning coffee run",
                offsetHours: 12,
                now: now
            )
        ]
        recordTotals[tokyo.id] = recordsByGroup[tokyo.id]?.count ?? 0

        recordsByGroup[apartment.id] = [
            fixtureRecord(
                id: "appstore-record-5",
                payer: "appstore-lina",
                amountMinor: "6280",
                participants: apartment.allMembers.map(\.uuid),
                category: "other",
                note: "Kitchen restock",
                offsetHours: 18,
                now: now
            ),
            fixtureRecord(
                id: "appstore-record-6",
                payer: "fixture-current-user",
                amountMinor: "4700",
                participants: apartment.allMembers.map(\.uuid),
                category: "shopping",
                note: "Cleaning supplies",
                offsetHours: 24,
                now: now
            )
        ]
        recordTotals[apartment.id] = recordsByGroup[apartment.id]?.count ?? 0
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

    private func fixtureMember(
        _ uuid: String,
        _ name: String,
        debtMinor: MoneyMinor = "0",
        costMinor: MoneyMinor = "0",
        recordCount: Int = 0,
        isTemporary: Bool = false
    ) -> Member {
        Member(
            uuid: uuid,
            name: name,
            avatar: "",
            debtMinor: debtMinor,
            costMinor: costMinor,
            recordCount: recordCount,
            isTemporary: isTemporary
        )
    }

    private func fixtureRecord(
        id: String,
        payer: String,
        amountMinor: MoneyMinor,
        participants: [String],
        category: String,
        note: String,
        offsetHours: TimeInterval,
        now: TimeInterval
    ) -> WalkRecord {
        let timestamp = now - (offsetHours * 60 * 60 * 1000)
        return WalkRecord(
            recordId: id,
            who: payer,
            paidMinor: amountMinor,
            forWhom: participants,
            type: category,
            text: note,
            long: "",
            lat: "",
            createdAt: timestamp,
            occurredAt: timestamp,
            modifiedAt: timestamp,
            isDebtResolve: false
        )
    }
}
#endif
