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
    @Published private(set) var groupTotal = 0
    @Published private(set) var isLoadingMoreGroups = false
    @Published var isBootstrapping = true
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var themeColorId: String = UserDefaults.standard.string(forKey: "themeColor") ?? "blue"
    @Published var isFixtureMode = false
    @Published private var recordSearchResultsByKey: [String: [WalkRecord]] = [:]
    @Published private var recordSearchTotalsByKey: [String: Int] = [:]
    @Published private var memberRecordsByKey: [String: [WalkRecord]] = [:]
    @Published private var memberRecordTotalsByKey: [String: Int] = [:]
    @Published private var loadingRecordKeys: Set<String> = []

    let api = APIClient()
    private let groupPageSize = 20
    private let recordPageSize = 10
    private var groupsPage = 0
    private var groupSearchQuery = ""

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
        if let fixture = WalkcalcDebugFixture.current {
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
        recordTotals = [:]
        groupTotal = 0
        groupsPage = 0
        groupSearchQuery = ""
        recordSearchResultsByKey = [:]
        recordSearchTotalsByKey = [:]
        memberRecordsByKey = [:]
        memberRecordTotalsByKey = [:]
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

    var canLoadMoreGroups: Bool {
        groups.count < groupTotal
    }

    func refreshHome(search: String? = nil) async {
        if isFixtureMode { return }
        guard let token else { return }
        let query = normalizedQuery(search)
        do {
            let response = try await api.groups(page: 1, pageSize: groupPageSize, search: optionalQuery(query), token: token)
            applyRefreshedToken(response)
            if response.success {
                groupSearchQuery = query
                groups = response.data ?? []
                groupsPage = response.pagination?.page ?? 1
                groupTotal = response.pagination?.total ?? groups.count
            } else {
                errorMessage = response.message ?? L("Network issues")
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func loadMoreGroups() async {
        if isFixtureMode { return }
        guard let token, canLoadMoreGroups, !isLoadingMoreGroups else { return }
        isLoadingMoreGroups = true
        defer { isLoadingMoreGroups = false }
        do {
            let response = try await api.groups(page: groupsPage + 1, pageSize: groupPageSize, search: optionalQuery(groupSearchQuery), token: token)
            applyRefreshedToken(response)
            if response.success {
                appendGroups(response.data ?? [])
                groupsPage = response.pagination?.page ?? groupsPage + 1
                groupTotal = response.pagination?.total ?? groupTotal
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
            async let recordsResponse = api.records(groupCode: id, page: 1, pageSize: recordPageSize, token: token)
            let (groupResult, recordResult) = try await (groupResponse, recordsResponse)
            applyRefreshedToken(groupResult)
            applyRefreshedToken(recordResult)
            if groupResult.success, let group = groupResult.data {
                replaceGroup(group)
            }
            if recordResult.success {
                clearRecordCaches(for: id)
                recordsByGroup[id] = recordResult.data ?? []
                recordTotals[id] = recordResult.pagination?.total ?? recordResult.data?.count ?? 0
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func loadMoreRecords(groupId: String, search: String = "") async {
        if isFixtureMode { return }
        guard let token else { return }
        let query = normalizedQuery(search)
        let key = recordListKey(groupId: groupId, search: query)
        guard !loadingRecordKeys.contains(key) else { return }

        if !query.isEmpty && recordSearchResultsByKey[key] == nil {
            await searchRecords(groupId: groupId, query: query)
            return
        }

        let current = cachedRecords(groupId: groupId, search: query)
        let total = cachedRecordTotal(groupId: groupId, search: query)
        guard current.count < total else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        let page = current.count / recordPageSize + 1
        do {
            let response = try await api.records(groupCode: groupId, page: page, pageSize: recordPageSize, recordSearch: recordSearchRequest(for: query), token: token)
            applyRefreshedToken(response)
            if response.success {
                let localMatches = query.isEmpty ? [] : localSearchMatches(groupId: groupId, query: query)
                if query.isEmpty {
                    recordsByGroup[groupId] = current + (response.data ?? [])
                    recordTotals[groupId] = response.pagination?.total ?? total
                } else {
                    let merged = mergedRecords(current + (response.data ?? []), with: localMatches)
                    recordSearchResultsByKey[key] = merged
                    recordSearchTotalsByKey[key] = max(response.pagination?.total ?? total, merged.count)
                }
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func records(groupId: String, search: String = "") -> [WalkRecord] {
        let query = normalizedQuery(search)
        guard !query.isEmpty else {
            return recordsByGroup[groupId] ?? []
        }
        let key = recordListKey(groupId: groupId, search: query)
        let localMatches = localSearchMatches(groupId: groupId, query: query)
        if let remote = recordSearchResultsByKey[key] {
            return mergedRecords(remote, with: localMatches)
        }
        return localMatches
    }

    func isLoadingRecords(groupId: String, search: String = "") -> Bool {
        let query = normalizedQuery(search)
        return loadingRecordKeys.contains(recordListKey(groupId: groupId, search: query))
    }

    func hasLoadedSearchRecords(groupId: String, search: String) -> Bool {
        let query = normalizedQuery(search)
        guard !query.isEmpty else { return true }
        return recordSearchResultsByKey[recordListKey(groupId: groupId, search: query)] != nil
    }

    func searchRecords(groupId: String, query rawQuery: String) async {
        let query = normalizedQuery(rawQuery)
        guard !query.isEmpty else { return }
        let key = recordListKey(groupId: groupId, search: query)
        if isFixtureMode {
            let matches = (recordsByGroup[groupId] ?? []).filter { localRecordMatches($0, query: query) }
            recordSearchResultsByKey[key] = matches
            recordSearchTotalsByKey[key] = matches.count
            return
        }
        guard let token else { return }
        guard !loadingRecordKeys.contains(key) else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        do {
            let response = try await api.records(groupCode: groupId, page: 1, pageSize: recordPageSize, recordSearch: recordSearchRequest(for: query), token: token)
            applyRefreshedToken(response)
            if response.success {
                let merged = mergedRecords(response.data ?? [], with: localSearchMatches(groupId: groupId, query: query))
                recordSearchResultsByKey[key] = merged
                recordSearchTotalsByKey[key] = max(response.pagination?.total ?? response.data?.count ?? 0, merged.count)
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func memberRecords(groupId: String, memberId: String) -> [WalkRecord] {
        let key = memberRecordKey(groupId: groupId, memberId: memberId)
        if let records = memberRecordsByKey[key] {
            return records
        }
        return (recordsByGroup[groupId] ?? []).filter { recordIncludesParticipant($0, participantId: memberId) }
    }

    func memberRecordTotal(groupId: String, memberId: String) -> Int {
        let key = memberRecordKey(groupId: groupId, memberId: memberId)
        return memberRecordTotalsByKey[key] ?? memberRecords(groupId: groupId, memberId: memberId).count
    }

    func refreshMemberRecords(groupId: String, memberId: String) async {
        let key = memberRecordKey(groupId: groupId, memberId: memberId)
        if isFixtureMode {
            let matches = (recordsByGroup[groupId] ?? []).filter { recordIncludesParticipant($0, participantId: memberId) }
            memberRecordsByKey[key] = matches
            memberRecordTotalsByKey[key] = matches.count
            return
        }
        guard let token else { return }
        guard !loadingRecordKeys.contains(key) else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        do {
            let response = try await api.records(groupCode: groupId, page: 1, pageSize: recordPageSize, participantId: memberId, token: token)
            applyRefreshedToken(response)
            if response.success {
                memberRecordsByKey[key] = response.data ?? []
                memberRecordTotalsByKey[key] = response.pagination?.total ?? response.data?.count ?? 0
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func loadMoreMemberRecords(groupId: String, memberId: String) async {
        if isFixtureMode { return }
        guard let token else { return }
        let key = memberRecordKey(groupId: groupId, memberId: memberId)
        guard !loadingRecordKeys.contains(key) else { return }
        let current = memberRecordsByKey[key] ?? []
        let total = memberRecordTotalsByKey[key] ?? current.count
        guard current.count < total else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        do {
            let page = current.count / recordPageSize + 1
            let response = try await api.records(groupCode: groupId, page: page, pageSize: recordPageSize, participantId: memberId, token: token)
            applyRefreshedToken(response)
            if response.success {
                memberRecordsByKey[key] = current + (response.data ?? [])
                memberRecordTotalsByKey[key] = response.pagination?.total ?? total
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
                type: transferCategory.id,
                text: "resolve",
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

    private func appendGroups(_ nextGroups: [WalkGroup]) {
        for group in nextGroups {
            replaceGroup(group)
        }
    }

    private func clearRecordCaches(for groupId: String) {
        recordSearchResultsByKey = recordSearchResultsByKey.filter { !$0.key.hasPrefix("\(groupId)::records::") }
        recordSearchTotalsByKey = recordSearchTotalsByKey.filter { !$0.key.hasPrefix("\(groupId)::records::") }
        memberRecordsByKey = memberRecordsByKey.filter { !$0.key.hasPrefix("\(groupId)::member::") }
        memberRecordTotalsByKey = memberRecordTotalsByKey.filter { !$0.key.hasPrefix("\(groupId)::member::") }
    }

    private func cachedRecords(groupId: String, search: String) -> [WalkRecord] {
        guard !search.isEmpty else {
            return recordsByGroup[groupId] ?? []
        }
        return recordSearchResultsByKey[recordListKey(groupId: groupId, search: search)] ?? []
    }

    private func cachedRecordTotal(groupId: String, search: String) -> Int {
        guard !search.isEmpty else {
            let current = recordsByGroup[groupId] ?? []
            return recordTotals[groupId] ?? current.count
        }
        let key = recordListKey(groupId: groupId, search: search)
        return recordSearchTotalsByKey[key] ?? recordSearchResultsByKey[key]?.count ?? 0
    }

    private func recordListKey(groupId: String, search: String) -> String {
        "\(groupId)::records::\(search)"
    }

    private func memberRecordKey(groupId: String, memberId: String) -> String {
        "\(groupId)::member::\(memberId)"
    }

    private func normalizedQuery(_ query: String?) -> String {
        query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func optionalQuery(_ query: String) -> String? {
        query.isEmpty ? nil : query
    }

    private func recordSearchRequest(for query: String) -> RecordSearchRequest? {
        query.isEmpty ? nil : .noteOrCategoryName(query: query)
    }

    private func localSearchMatches(groupId: String, query: String) -> [WalkRecord] {
        (recordsByGroup[groupId] ?? []).filter { localRecordMatches($0, query: query) }
    }

    private func mergedRecords(_ primary: [WalkRecord], with secondary: [WalkRecord]) -> [WalkRecord] {
        var seenRecordIds = Set<String>()
        var result: [WalkRecord] = []
        for record in primary + secondary where seenRecordIds.insert(record.recordId).inserted {
            result.append(record)
        }
        return result
    }

    private func recordIncludesParticipant(_ record: WalkRecord, participantId: String) -> Bool {
        record.who == participantId || record.forWhom.contains(participantId)
    }

    private func localRecordMatches(_ record: WalkRecord, query: String) -> Bool {
        record.text.localizedCaseInsensitiveContains(query)
            || L(expenseCategory(for: record).titleKey).localizedCaseInsensitiveContains(query)
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
