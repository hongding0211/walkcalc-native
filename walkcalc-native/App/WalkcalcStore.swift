import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

@MainActor
final class WalkcalcStore: ObservableObject {
    @Published var token: String?
    @Published var user: UserProfile?
    @Published var groups: [WalkGroup] = []
    @Published var recordsByGroup: [String: [WalkRecord]] = [:]
    @Published var recordTotals: [String: Int] = [:]
    @Published var isBootstrapping = true
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var themeColorId: String = UserDefaults.standard.string(forKey: "themeColor") ?? "blue"
    @Published var isFixtureMode = false

    let api = APIClient()

    var primaryColor: Color {
        themeColorOptions.first(where: { $0.id == themeColorId })?.color ?? themeColorOptions[0].color
    }

    var primaryUIColor: UIColor {
        themeColorOptions.first(where: { $0.id == themeColorId })?.uiColor ?? themeColorOptions[0].uiColor
    }

    var isLoggedIn: Bool {
        token != nil && user != nil
    }

    init() {
        token = UserDefaults.standard.string(forKey: "walkcalc.token")
        #if DEBUG
        if let fixture = DebugFixture.current {
            applyDebugFixture(fixture)
        }
        #endif
    }

    func bootstrap() async {
        if isFixtureMode {
            isBootstrapping = false
            return
        }
        defer { isBootstrapping = false }
        guard let token else {
            return
        }
        await loadUser(token: token)
        if user != nil {
            await postUserMeta()
            await refreshHome()
        }
    }

    func setThemeColor(_ id: String) {
        themeColorId = id
        UserDefaults.standard.set(id, forKey: "themeColor")
    }

    func signIn(token: String) async {
        self.token = token
        UserDefaults.standard.set(token, forKey: "walkcalc.token")
        await loadUser(token: token)
        await postUserMeta()
        await refreshHome()
    }

    func logout() {
        token = nil
        user = nil
        groups = []
        recordsByGroup = [:]
        UserDefaults.standard.removeObject(forKey: "walkcalc.token")
    }

    func loadUser(token: String) async {
        do {
            let response = try await api.userInfo(token: token)
            applyRefreshedToken(response)
            if response.success, let data = response.data {
                user = data
            } else {
                logout()
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func postUserMeta() async {
        guard let token else { return }
        let metadata: [String: Any] = [
            "language": L10n.serverLanguageCode,
            "deviceInfo": [
                "os": "ios",
                "version": UIDevice.current.systemVersion
            ],
            "lastOpened": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let response = try? await api.postUserMeta(token: token, metadata: metadata) {
            applyRefreshedToken(response)
        }
    }

    func requestNotificationPermissionIfNeeded() async {
        if isFixtureMode { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func refreshHome() async {
        if isFixtureMode { return }
        guard let token else { return }
        do {
            let response = try await api.groups(token: token)
            applyRefreshedToken(response)
            if response.success {
                groups = response.data ?? []
            } else {
                errorMessage = response.message ?? L("Network issues")
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func group(id: String) -> WalkGroup? {
        groups.first(where: { $0.id == id })
    }

    func refreshGroup(_ id: String) async {
        if isFixtureMode { return }
        guard let token else { return }
        do {
            async let groupResponse = api.group(code: id, token: token)
            async let recordsResponse = api.records(groupCode: id, page: 1, token: token)
            let (groupResult, recordResult) = try await (groupResponse, recordsResponse)
            applyRefreshedToken(groupResult)
            applyRefreshedToken(recordResult)
            if groupResult.success, let group = groupResult.data {
                replaceGroup(group)
            }
            if recordResult.success {
                recordsByGroup[id] = recordResult.data ?? []
                recordTotals[id] = recordResult.pagination?.total ?? recordResult.data?.count ?? 0
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func loadMoreRecords(groupId: String) async {
        if isFixtureMode { return }
        guard let token else { return }
        let current = recordsByGroup[groupId] ?? []
        let total = recordTotals[groupId] ?? current.count
        guard current.count < total else { return }
        let page = current.count / 10 + 1
        do {
            let response = try await api.records(groupCode: groupId, page: page, token: token)
            applyRefreshedToken(response)
            if response.success {
                recordsByGroup[groupId] = current + (response.data ?? [])
                recordTotals[groupId] = response.pagination?.total ?? total
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func createGroup(name: String) async -> Bool {
        await createGroup(name: name, users: [], tempUsers: [])
    }

    func createGroup(name: String, users: [UserProfile], tempUsers: [String]) async -> Bool {
        if isFixtureMode {
            let groupId = "FIX-\(Int(Date().timeIntervalSince1970 * 1000))"
            let currentUser = user.map {
                Member(uuid: $0.uuid, name: $0.name, avatar: $0.avatar, debtMinor: "0", costMinor: "0")
            }
            let members = ([currentUser].compactMap { $0 }) + users.map {
                Member(uuid: $0.uuid, name: $0.name, avatar: $0.avatar, debtMinor: "0", costMinor: "0")
            }
            let temps = tempUsers.map {
                Member(uuid: "temp-\($0)", name: $0, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true)
            }
            groups.insert(WalkGroup(
                id: groupId,
                name: name,
                createdAt: Date().timeIntervalSince1970 * 1000,
                modifiedAt: Date().timeIntervalSince1970 * 1000,
                membersInfo: members,
                tempUsers: temps,
                archivedUsers: [],
                isOwner: true
            ), at: 0)
            recordsByGroup[groupId] = []
            recordTotals[groupId] = 0
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let response = try await api.createGroup(name: name, token: token)
            applyRefreshedToken(response)
            if response.success, let groupId = response.data, !groupId.isEmpty {
                if !users.isEmpty {
                    applyRefreshedToken(try await api.invite(code: groupId, userIds: users.map(\.uuid), token: token))
                }
                for tempUser in tempUsers where !tempUser.isEmpty {
                    applyRefreshedToken(try await api.addTempUser(code: groupId, name: tempUser, token: token))
                }
            }
            await refreshHome()
            return response.success
        }
    }

    func joinGroup(code: String) async -> Bool {
        return await withLoading {
            guard let token else { return false }
            let response = try await api.joinGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func archiveGroup(_ code: String) async -> Bool {
        if isFixtureMode, let user {
            guard let index = groups.firstIndex(where: { $0.id == code }) else { return false }
            if !groups[index].archivedUsers.contains(user.uuid) {
                groups[index].archivedUsers.append(user.uuid)
            }
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let response = try await api.archiveGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func unarchiveGroup(_ code: String) async -> Bool {
        if isFixtureMode, let user {
            guard let index = groups.firstIndex(where: { $0.id == code }) else { return false }
            groups[index].archivedUsers.removeAll { $0 == user.uuid }
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let response = try await api.unarchiveGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func deleteGroup(_ code: String) async -> Bool {
        if isFixtureMode {
            groups.removeAll { $0.id == code }
            recordsByGroup[code] = nil
            recordTotals[code] = nil
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let response = try await api.deleteGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func changeGroupName(_ code: String, name: String) async -> Bool {
        if isFixtureMode {
            guard let index = groups.firstIndex(where: { $0.id == code }) else { return false }
            groups[index].name = name
            groups[index].modifiedAt = Date().timeIntervalSince1970 * 1000
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let response = try await api.changeGroupName(code: code, name: name, token: token)
            applyRefreshedToken(response)
            await refreshGroup(code)
            return response.success
        }
    }

    func addMembers(groupId: String, users: [UserProfile], tempUsers: [String]) async -> Bool {
        if isFixtureMode {
            guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return false }
            for user in users where !groups[index].membersInfo.contains(where: { $0.uuid == user.uuid }) {
                groups[index].membersInfo.append(Member(uuid: user.uuid, name: user.name, avatar: user.avatar, debtMinor: "0", costMinor: "0"))
            }
            for tempUser in tempUsers where !tempUser.isEmpty {
                groups[index].tempUsers.append(Member(uuid: "temp-\(tempUser)-\(groups[index].tempUsers.count)", name: tempUser, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true))
            }
            return true
        }
        return await withLoading {
            guard let token else { return false }
            if !users.isEmpty {
                applyRefreshedToken(try await api.invite(code: groupId, userIds: users.map(\.uuid), token: token))
            }
            for tempUser in tempUsers where !tempUser.isEmpty {
                applyRefreshedToken(try await api.addTempUser(code: groupId, name: tempUser, token: token))
            }
            await refreshGroup(groupId)
            return true
        }
    }

    func searchUsers(name: String) async -> [UserProfile] {
        if isFixtureMode {
            let names = ["Alexandra", "Christopher", "Noah", "Ivy", "Owen", "Tara", "June", "Keith", "Lin", "Ming", "Yan"]
            return names
                .filter { $0.localizedCaseInsensitiveContains(name) }
                .map { UserProfile(uuid: "fixture-\($0)", name: $0, avatar: "") }
        }
        guard let token, !name.isEmpty else { return [] }
        do {
            let response = try await api.searchUsers(name: name, token: token)
            applyRefreshedToken(response)
            return response.data ?? []
        } catch {
            return []
        }
    }

    func addRecord(groupId: String, who: String, paid: String, forWhom: [String], type: String, text: String, long: String = "", lat: String = "") async -> Bool {
        if isFixtureMode {
            guard let paidMinor = try? Money.parseDisplay(paid), !Money.isZero(paidMinor) else { return false }
            let record = WalkRecord(
                recordId: "fixture-record-\(Int(Date().timeIntervalSince1970 * 1000))",
                who: who,
                paidMinor: paidMinor,
                forWhom: forWhom,
                type: type,
                text: text,
                long: long,
                lat: lat,
                createdAt: Date().timeIntervalSince1970 * 1000,
                modifiedAt: Date().timeIntervalSince1970 * 1000,
                isDebtResolve: false
            )
            recordsByGroup[groupId, default: []].insert(record, at: 0)
            recordTotals[groupId] = recordsByGroup[groupId]?.count ?? 0
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let paidMinor = try Money.parseDisplay(paid)
            guard !Money.isZero(paidMinor) else { return false }
            let response = try await api.addRecord(groupCode: groupId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, token: token, long: long, lat: lat)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func editRecord(groupId: String, recordId: String, who: String, paid: String, forWhom: [String], type: String, text: String) async -> Bool {
        if isFixtureMode {
            guard let paidMinor = try? Money.parseDisplay(paid),
                  let index = recordsByGroup[groupId]?.firstIndex(where: { $0.recordId == recordId }) else { return false }
            recordsByGroup[groupId]?[index].who = who
            recordsByGroup[groupId]?[index].paidMinor = paidMinor
            recordsByGroup[groupId]?[index].forWhom = forWhom
            recordsByGroup[groupId]?[index].type = type
            recordsByGroup[groupId]?[index].text = text
            recordsByGroup[groupId]?[index].modifiedAt = Date().timeIntervalSince1970 * 1000
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let paidMinor = try Money.parseDisplay(paid)
            guard !Money.isZero(paidMinor) else { return false }
            let response = try await api.updateRecord(groupCode: groupId, recordId: recordId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func deleteRecord(groupId: String, recordId: String) async -> Bool {
        if isFixtureMode {
            recordsByGroup[groupId]?.removeAll { $0.recordId == recordId }
            recordTotals[groupId] = recordsByGroup[groupId]?.count ?? 0
            return true
        }
        return await withLoading {
            guard let token else { return false }
            let response = try await api.dropRecord(groupCode: groupId, recordId: recordId, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func resolveSingle(groupId: String, debt: ResolvedDebt) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.addRecord(
                groupCode: groupId,
                who: debt.from.uuid,
                paidMinor: debt.amountMinor,
                forWhom: [debt.to.uuid],
                type: "debtResolve",
                text: L("Debt Resolve"),
                token: token,
                isDebtResolve: true
            )
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func resolveAll(groupId: String, debts: [ResolvedDebt]) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let transfers = debts.map { ["from": $0.from.uuid, "to": $0.to.uuid, "amountMinor": $0.amountMinor] }
            let response = try await api.resolveDebts(groupCode: groupId, transfers: transfers, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func totalDebtMinor() -> MoneyMinor {
        guard let user else { return "0" }
        return groups.reduce("0") { sum, group in
            let mine = group.membersInfo.first(where: { $0.uuid == user.uuid })?.debtMinor ?? "0"
            return Money.add(sum, mine)
        }
    }

    func resolvedDebts(for group: WalkGroup) -> [ResolvedDebt] {
        var receivers = group.allMembers
            .filter { Money.compare($0.debtMinor, "0") != .orderedAscending }
            .sorted { Money.compare($0.debtMinor, $1.debtMinor) == .orderedDescending }
        var payers = group.allMembers
            .filter { Money.compare($0.debtMinor, "0") == .orderedAscending }
            .map { member -> Member in
                var next = member
                next.debtMinor = Money.negate(member.debtMinor)
                return next
            }
            .sorted { Money.compare($0.debtMinor, $1.debtMinor) == .orderedDescending }

        let receiverTotal = receivers.reduce("0") { Money.add($0, $1.debtMinor) }
        let payerTotal = payers.reduce("0") { Money.add($0, $1.debtMinor) }
        guard Money.compare(receiverTotal, payerTotal) == .orderedSame else {
            return []
        }

        var result: [ResolvedDebt] = []
        for receiverIndex in receivers.indices {
            while !Money.isZero(receivers[receiverIndex].debtMinor) {
                var advanced = false
                for payerIndex in payers.indices where !Money.isZero(payers[payerIndex].debtMinor) {
                    advanced = true
                    if Money.compare(receivers[receiverIndex].debtMinor, payers[payerIndex].debtMinor) != .orderedAscending {
                        result.append(ResolvedDebt(from: payers[payerIndex], to: receivers[receiverIndex], amountMinor: payers[payerIndex].debtMinor))
                        receivers[receiverIndex].debtMinor = Money.add(receivers[receiverIndex].debtMinor, Money.negate(payers[payerIndex].debtMinor))
                        payers[payerIndex].debtMinor = "0"
                    } else {
                        result.append(ResolvedDebt(from: payers[payerIndex], to: receivers[receiverIndex], amountMinor: receivers[receiverIndex].debtMinor))
                        payers[payerIndex].debtMinor = Money.add(payers[payerIndex].debtMinor, Money.negate(receivers[receiverIndex].debtMinor))
                        receivers[receiverIndex].debtMinor = "0"
                        break
                    }
                }
                if !advanced {
                    break
                }
            }
        }
        return result
    }

    private func replaceGroup(_ group: WalkGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
    }

    private func applyRefreshedToken<T>(_ response: APIEnvelope<T>) {
        guard let refreshedToken = response.refreshedToken else {
            return
        }
        token = refreshedToken
        UserDefaults.standard.set(refreshedToken, forKey: "walkcalc.token")
    }

    private func withLoading(_ action: () async throws -> Bool) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            return try await action()
        } catch {
            errorMessage = L("Network issues")
            return false
        }
    }
}

#if DEBUG
private enum DebugFixture: String {
    case empty = "--ui-fixture-empty"
    case peopleSetup = "--ui-fixture-people-empty"
    case emptyBalance = "--ui-fixture-empty-balance"
    case stress = "--ui-fixture-stress"
    case edge = "--ui-fixture-edge"

    static var current: DebugFixture? {
        ProcessInfo.processInfo.arguments.compactMap(DebugFixture.init(rawValue:)).first
    }
}

@MainActor
private extension WalkcalcStore {
    func applyDebugFixture(_ fixture: DebugFixture) {
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
    }

    func applyStressFixture() {
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
                modifiedAt: timestamp,
                isDebtResolve: false
            ))
        }

        recordsByGroup["stress-0"] = records
        recordTotals["stress-0"] = records.count
    }

    func applyEdgeFixture() {
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
                modifiedAt: Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000,
                isDebtResolve: false
            )
        ]
        recordTotals[group.id] = recordsByGroup[group.id]?.count ?? 0
    }

    func fixtureGroup(id: String, name: String, members: [Member], tempUsers: [Member]) -> WalkGroup {
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

    func fixtureMember(_ uuid: String, _ name: String, isTemporary: Bool = false) -> Member {
        Member(uuid: uuid, name: name, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: isTemporary)
    }
}
#endif
