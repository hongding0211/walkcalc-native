#if DEBUG
import Foundation
import UIKit

enum WalkcalcDebugFixture: String {
    case empty = "--ui-fixture-empty"
    case peopleSetup = "--ui-fixture-people-empty"
    case emptyBalance = "--ui-fixture-empty-balance"
    case stress = "--ui-fixture-stress"
    case scroll = "--ui-fixture-scroll"
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
        user = UserProfile(uuid: "fixture-current-user", name: "Hong", avatar: appStoreAvatarHong)
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
        case .scroll:
            applyStressFixture()
            groups = Array(groups.prefix(1))
            groups[0].name = "Scroll verification"
            let balances = ["CNY", "EUR", "USD"].enumerated().map { index, code in
                MemberCurrencyProjection(currencyCode: code, debtMinor: "\((index + 1) * 100)",
                    costMinor: "100", paidTotalMinor: "200", recordCount: 60,
                    settlementInMinor: "0", settlementOutMinor: "0")
            }
            groups[0].hasCurrentUserBalanceSummary = true
            groups[0].currentUserCurrencyBalances = balances
            groups[0].currentUserRecordCount = 180
            groups[0].membersInfo[0].currencyBalances = balances
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: Date())
            recordsByGroup["stress-0"] = (recordsByGroup["stress-0"] ?? []).enumerated().map { index, record in
                var record = record
                let day = calendar.date(byAdding: .day, value: -(index / 6), to: today) ?? today
                record.occurredAt = day.addingTimeInterval(Double(6 - index % 6) * 600).timeIntervalSince1970 * 1000
                return record
            }
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
                fixtureMember("fixture-current-user", "Hong", debtMinor: "4320", costMinor: "18840", recordCount: 4, avatar: appStoreAvatarHong),
                fixtureMember("appstore-ava", "Ava", debtMinor: "-2160", costMinor: "12480", recordCount: 3, avatar: appStoreAvatarAva),
                fixtureMember("appstore-noah", "Noah", debtMinor: "-1260", costMinor: "9360", recordCount: 3, avatar: appStoreAvatarNoah),
                fixtureMember("appstore-mia", "Mia", debtMinor: "-900", costMinor: "8160", recordCount: 2, avatar: appStoreAvatarMia)
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
                fixtureMember("fixture-current-user", "Hong", debtMinor: "-1850", costMinor: "7340", recordCount: 2, avatar: appStoreAvatarHong),
                fixtureMember("appstore-lina", "Lina", debtMinor: "1850", costMinor: "9190", recordCount: 2, avatar: appStoreAvatarLina)
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

        if ProcessInfo.processInfo.arguments.contains("--ui-poster-data") {
            let english = Locale.preferredLanguages.first?.hasPrefix("en") == true
            groups[0].name = english ? "Our next adventure" : "一起去旅行"
            groups[1].name = english ? "Everyday together" : "我们的日常"
            let names = english ? ["Dinner around the corner", "Two nights away", "Airport express", "Coffee on the go"] : ["晚餐 · 街角小馆", "住宿 · 两晚的好梦", "交通 · 机场快线", "咖啡 · 慢慢逛"]
            var records = recordsByGroup[tokyo.id] ?? []
            for i in records.indices { records[i].text = names[i]; records[i].currencyCode = "CNY" }
            for (index, code, amount, note) in [(4, "USD", "12800", "门票 · 一起看世界"), (5, "EUR", "9600", "午餐 · 旅途中的小聚")] {
                var record = fixtureRecord(id: "poster-\(index)", payer: "fixture-current-user", amountMinor: amount,
                    participants: tokyo.allMembers.map(\.uuid), category: "food", note: note, offsetHours: Double(index), now: now)
                record.currencyCode = code
                if english { record.text = index == 4 ? "A day to explore" : "Lunch with a view" }
                records.append(record)
            }
            recordsByGroup[tokyo.id] = records
            recordTotals[tokyo.id] = records.count
            for m in groups[0].membersInfo.indices {
                let id = groups[0].membersInfo[m].uuid
                let projections = ["CNY", "USD", "EUR"].map { code in
                    let matching = records.filter { $0.currencyCode == code }
                    let paid = matching.filter { $0.who == id }.reduce(0) { $0 + (Int($1.paidMinor) ?? 0) }
                    let cost = matching.filter { $0.forWhom.contains(id) }.reduce(0) { $0 + (Int($1.paidMinor) ?? 0) / $1.forWhom.count }
                    return MemberCurrencyProjection(currencyCode: code, debtMinor: String(paid-cost), costMinor: String(cost),
                        paidTotalMinor: String(paid), recordCount: matching.filter { $0.forWhom.contains(id) }.count,
                        settlementInMinor: "0", settlementOutMinor: "0")
                }
                groups[0].membersInfo[m].currencyBalances = projections
                groups[0].membersInfo[m].debtMinor = projections[0].debtMinor
                groups[0].membersInfo[m].costMinor = projections[0].costMinor
                groups[0].membersInfo[m].recordCount = records.filter { $0.forWhom.contains(id) }.count
                if m == 0 {
                    groups[0].currentUserCurrencyBalances = projections
                    groups[0].currentUserBalanceMinor = projections[0].debtMinor
                    groups[0].currentUserExpenseShareMinor = projections[0].costMinor
                    groups[0].currentUserPaidTotalMinor = projections[0].paidTotalMinor
                    groups[0].currentUserRecordCount = groups[0].membersInfo[m].recordCount
                }
            }
            applyPosterScenarios()
            // Apply a screenshot-only native split width after SwiftUI installs its controllers.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                func configure(_ controller: UIViewController) {
                    if let split = controller as? UISplitViewController,
                       split.view.bounds.width > split.view.bounds.height {
                        let width = split.view.bounds.width * 0.38
                        split.maximumPrimaryColumnWidth = width
                        split.minimumPrimaryColumnWidth = width
                        split.preferredPrimaryColumnWidthFraction = 0.38
                        split.view.setNeedsLayout()
                    }
                    controller.children.forEach(configure)
                }
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    for window in scene.windows {
                        if let root = window.rootViewController { configure(root) }
                    }
                }
            }
        }
    }

    // Marketing scenarios use real ledger projections and the production wallet palette.
    private func applyPosterScenarios() {
        let english = Locale.preferredLanguages.first?.hasPrefix("en") == true
        let ids = ["fixture-current-user", "appstore-ava", "appstore-noah"]
        let members = [fixtureMember(ids[0], "Hong", avatar: appStoreAvatarHong),
                       fixtureMember(ids[1], "Ava", avatar: appStoreAvatarAva),
                       fixtureMember(ids[2], "Noah", avatar: appStoreAvatarNoah)]
        let now = Date().timeIntervalSince1970 * 1000
        func add(_ id: String, _ name: String, _ defaultCode: String,
                 _ entries: [(String, String, String, String)], settled: Set<String> = []) {
            var group = fixtureGroup(id: id, name: name, members: members, tempUsers: [])
            group.currencyCode = defaultCode
            var records: [WalkRecord] = []
            for (index, entry) in entries.enumerated() {
                var record = fixtureRecord(id: "\(id)-\(index)", payer: ids[0], amountMinor: entry.1,
                    participants: ids, category: entry.2, note: entry.3, offsetHours: Double(index), now: now)
                record.currencyCode = entry.0
                records.append(record)
                if settled.contains(entry.0) {
                    for other in ids.dropFirst() {
                        var transfer = fixtureRecord(id: "\(id)-\(index)-\(other)", payer: other,
                            amountMinor: String((Int(entry.1) ?? 0) / ids.count), participants: [ids[0]],
                            category: "transfer", note: "", offsetHours: 0, now: now)
                        transfer.currencyCode = entry.0
                        transfer.isDebtResolve = true
                        records.append(transfer)
                    }
                }
            }
            let codes = Array(Set(entries.map { $0.0 })).sorted()
            for m in group.membersInfo.indices {
                let member = ids[m]
                let projections = codes.map { code in
                    let all = records.filter { $0.currencyCode == code }
                    let expenses = all.filter { !$0.isDebtResolve }
                    let paid = expenses.filter { $0.who == member }.reduce(0) { $0 + (Int($1.paidMinor) ?? 0) }
                    let cost = expenses.filter { $0.forWhom.contains(member) }.reduce(0) { $0 + (Int($1.paidMinor) ?? 0) / $1.forWhom.count }
                    let incoming = all.filter { $0.isDebtResolve && $0.forWhom.contains(member) }.reduce(0) { $0 + (Int($1.paidMinor) ?? 0) }
                    let outgoing = all.filter { $0.isDebtResolve && $0.who == member }.reduce(0) { $0 + (Int($1.paidMinor) ?? 0) }
                    return MemberCurrencyProjection(currencyCode: code, debtMinor: String(paid-cost-incoming+outgoing),
                        costMinor: String(cost), paidTotalMinor: String(paid), recordCount: expenses.count,
                        settlementInMinor: String(incoming), settlementOutMinor: String(outgoing))
                }
                group.membersInfo[m].currencyBalances = projections
                group.membersInfo[m].recordCount = entries.count
                let primary = projections.first { $0.currencyCode == defaultCode }!
                group.membersInfo[m].debtMinor = primary.debtMinor
                group.membersInfo[m].costMinor = primary.costMinor
                if m == 0 {
                    group.hasCurrentUserBalanceSummary = true
                    group.currentUserCurrencyBalances = projections
                    group.currentUserBalanceMinor = primary.debtMinor
                    group.currentUserExpenseShareMinor = primary.costMinor
                    group.currentUserPaidTotalMinor = primary.paidTotalMinor
                    group.currentUserRecordCount = entries.count
                }
            }
            group.participantCount = members.count
            group.participantPreview = group.membersInfo
            group.serverHasUnresolvedBalance = group.membersInfo.contains { $0.hasUnresolvedCurrencyBalance }
            groups.append(group)
            recordsByGroup[id] = records
            recordTotals[id] = records.count
        }
        add("poster-europe", english ? "Europe with friends" : "和朋友去欧洲", "EUR", [
            ("EUR", "38400", "accommodation", english ? "Three nights in Paris" : "巴黎的三晚"),
            ("GBP", "12600", "food", english ? "Sunday lunch in London" : "伦敦周日午餐"),
            ("USD", "7200", "traffic", english ? "Airport ride" : "机场接送")])
        add("poster-tokyo", english ? "Tokyo weekend" : "东京周末", "JPY", [
            ("JPY", "1260000", "food", english ? "Sushi night" : "寿司之夜"),
            ("CNY", "28800", "traffic", english ? "Ride to the airport" : "出发去机场")], settled: ["JPY"])
        add("poster-dinner", english ? "Friday dinner" : "周五朋友聚餐", "USD", [
            ("USD", "3600", "beverage", english ? "Drinks with friends" : "朋友小酌")])
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
            ownerUserId: members.first?.uuid,
            isOwner: true
        )
    }

    private func fixtureMember(
        _ uuid: String,
        _ name: String,
        debtMinor: MoneyMinor = "0",
        costMinor: MoneyMinor = "0",
        recordCount: Int = 0,
        isTemporary: Bool = false,
        avatar: String = ""
    ) -> Member {
        Member(
            uuid: uuid,
            name: name,
            avatar: avatar,
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

    private var appStoreAvatarHong: String {
        if ProcessInfo.processInfo.arguments.contains("--ui-poster-data") {
            return "http://127.0.0.1:8788/assets/avatars/cat.png"
        }
        return "https://images.unsplash.com/photo-1672527838035-90ae2ad2e813?auto=format&fit=crop&crop=faces&w=160&h=160&q=80"
    }

    private var appStoreAvatarAva: String {
        if ProcessInfo.processInfo.arguments.contains("--ui-poster-data") {
            return "http://127.0.0.1:8788/assets/avatars/dog.png"
        }
        return "https://images.unsplash.com/photo-1769961982389-bb243681421a?auto=format&fit=crop&crop=faces&w=160&h=160&q=80"
    }

    private var appStoreAvatarNoah: String {
        if ProcessInfo.processInfo.arguments.contains("--ui-poster-data") {
            return "http://127.0.0.1:8788/assets/avatars/rabbit.png"
        }
        return "https://images.unsplash.com/photo-1758600587808-9e251cf34b94?auto=format&fit=crop&crop=faces&w=160&h=160&q=80"
    }

    private var appStoreAvatarMia: String {
        if ProcessInfo.processInfo.arguments.contains("--ui-poster-data") {
            return "http://127.0.0.1:8788/assets/avatars/dog.png"
        }
        return "https://images.unsplash.com/photo-1581065178047-8ee15951ede6?auto=format&fit=crop&crop=faces&w=160&h=160&q=80"
    }

    private var appStoreAvatarLina: String {
        if ProcessInfo.processInfo.arguments.contains("--ui-poster-data") {
            return "http://127.0.0.1:8788/assets/avatars/rabbit.png"
        }
        return "https://images.unsplash.com/photo-1758611969976-9f38286119ef?auto=format&fit=crop&crop=faces&w=160&h=160&q=80"
    }
}
#endif
