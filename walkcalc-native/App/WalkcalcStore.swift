import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit
import OSLog

@MainActor
struct JoinGroupResult {
    let success: Bool
    let message: String?
}

@MainActor
struct StoreActionResult {
    let success: Bool
    let message: String?

    static var success: StoreActionResult {
        StoreActionResult(success: true, message: nil)
    }

    static func failure(_ message: String?) -> StoreActionResult {
        StoreActionResult(success: false, message: message)
    }
}

struct StoreAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum NetworkOperationIntent: String {
    case bootstrapAuth
    case backgroundRefresh
    case pagination
    case secondaryLoad
    case userAction
    case dataLossSensitiveMutation
}

private enum FeedbackDisposition: String {
    case silent
    case local
    case nonBlockingNotice
    case urgentAlert
}

@MainActor
final class WalkcalcStore: ObservableObject {
    @Published var token: String?
    @Published var user: UserProfile?
    @Published var groups: [WalkGroup] = []
    @Published var recordsByGroup: [String: [WalkRecord]] = [:]
    @Published var recordTotals: [String: Int] = [:]
    @Published var totalBalanceMinor: MoneyMinor = "0"
    @Published private(set) var groupTotal = 0
    @Published private(set) var isLoadingMoreGroups = false
    @Published var isBootstrapping = true
    @Published private(set) var isSigningIn = false
    @Published var urgentAlert: StoreAlert?
    @Published var selectedTheme: AppTheme = AppTheme.load()
    @Published var isFixtureMode = false
    @Published private var recordSearchResultsByKey: [String: [WalkRecord]] = [:]
    @Published private var recordSearchTotalsByKey: [String: Int] = [:]
    @Published private var memberRecordsByKey: [String: [WalkRecord]] = [:]
    @Published private var memberRecordTotalsByKey: [String: Int] = [:]
    @Published private var settlementSuggestionsByGroup: [String: [SettlementTransfer]] = [:]
    @Published private var loadingRecordKeys: Set<String> = []

    let api = APIClient()
    private let groupPageSize = 20
    private let recordPageSize = 10
    private var groupsPage = 0
    private var groupSearchQuery = ""
    private var apnsProviderToken = UserDefaults.standard.string(forKey: "walkcalc.apnsProviderToken")
    private var pushDeviceRegistrationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private let networkFeedbackLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "walkcalc-native", category: "NetworkFeedback")

    var primaryColor: Color {
        selectedTheme.accent
    }

    var primaryUIColor: UIColor {
        selectedTheme.accentUIColor
    }

    var isLoggedIn: Bool {
        token != nil && user != nil
    }

    init() {
        token = UserDefaults.standard.string(forKey: "walkcalc.token")
        NotificationCenter.default.publisher(for: .walkcalcAPNsTokenDidChange)
            .compactMap { $0.object as? String }
            .receive(on: RunLoop.main)
            .sink { [weak self] providerToken in
                Task { @MainActor in
                    await self?.handleAPNsProviderToken(providerToken)
                }
            }
            .store(in: &cancellables)
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
            await registerPushDeviceIfPossible(reason: "app_open")
            if api.ledgerAPIEnabled {
                await refreshHome()
            } else {
                resetLedgerState()
            }
        }
    }

    func prepareNetworkAccessForStartup() async {
        guard !isFixtureMode else { return }
        await api.warmUpNetworkAccess()
    }

    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
        theme.persist()
    }

    func setThemeColor(_ id: String) {
        setTheme(AppTheme(rawValue: id) ?? AppTheme.theme(forLegacyValue: id))
    }

    func signIn(token: String) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        self.token = token
        UserDefaults.standard.set(token, forKey: "walkcalc.token")

        guard let signedInUser = await fetchUser(token: token) else {
            return
        }

        user = signedInUser
        await registerPushDeviceIfPossible(reason: "sign_in")
        if api.ledgerAPIEnabled {
            guard await refreshHome() else {
                return
            }
        } else {
            resetLedgerState()
        }
    }

    func logout() {
        token = nil
        user = nil
        resetLedgerState()
        isSigningIn = false
        UserDefaults.standard.removeObject(forKey: "walkcalc.token")
    }

    private func resetLedgerState() {
        groups = []
        recordsByGroup = [:]
        recordTotals = [:]
        groupTotal = 0
        totalBalanceMinor = "0"
        groupsPage = 0
        groupSearchQuery = ""
        recordSearchResultsByKey = [:]
        recordSearchTotalsByKey = [:]
        memberRecordsByKey = [:]
        memberRecordTotalsByKey = [:]
        settlementSuggestionsByGroup = [:]
    }

    func loadUser(token: String) async {
        user = await fetchUser(token: token)
    }

    private func fetchUser(token: String) async -> UserProfile? {
        do {
            let response = try await api.userInfo(token: token)
            applyRefreshedToken(response)
            if response.success, let data = response.data {
                return data
            } else {
                logout()
                return nil
            }
        } catch {
            recordFailure(operation: "fetchUser", intent: .bootstrapAuth, disposition: .silent, error: error)
            return nil
        }
    }

    func requestNotificationPermissionIfNeeded() async {
        if isFixtureMode { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            UIApplication.shared.registerForRemoteNotifications()
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            UIApplication.shared.registerForRemoteNotifications()
        @unknown default:
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func handleAPNsProviderToken(_ providerToken: String) async {
        apnsProviderToken = providerToken
        UserDefaults.standard.set(providerToken, forKey: "walkcalc.apnsProviderToken")
        await registerPushDeviceIfPossible(reason: "apns_token")
    }

    private func registerPushDeviceIfPossible(reason: String) async {
        guard !isFixtureMode else { return }
        guard let token else { return }
        guard let providerToken = apnsProviderToken, !providerToken.isEmpty else { return }

        if pushDeviceRegistrationTask != nil {
            return
        }

        let api = api
        pushDeviceRegistrationTask = Task {
            defer {
                Task { @MainActor in
                    self.pushDeviceRegistrationTask = nil
                }
            }
            if let response = try? await api.registerPushDevice(
                token: token,
                payload: pushDeviceRegistrationPayload(providerToken: providerToken, reason: reason)
            ) {
                await MainActor.run {
                    self.applyRefreshedToken(response)
                }
            }
        }

        await pushDeviceRegistrationTask?.value
    }

    private func pushDeviceRegistrationPayload(providerToken: String, reason: String) -> [String: Any] {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let device = UIDevice.current
        return [
            "appId": ProcessInfo.processInfo.environment["WALKCALC_PUSH_APP_ID"] ?? "walkcalc-ios",
            "platform": "ios",
            "providerToken": providerToken,
            "environment": pushEnvironment,
            "locale": L10n.serverLanguageCode,
            "deviceId": stablePushDeviceId,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "bundleId": bundle.bundleIdentifier ?? "",
            "deviceModel": device.model,
            "metadata": [
                "client": "walkcalc-native",
                "reason": reason,
                "systemName": device.systemName,
                "systemVersion": device.systemVersion,
                "interfaceIdiom": interfaceIdiomName(device.userInterfaceIdiom)
            ]
        ]
    }

    private var pushEnvironment: String {
        if let environment = ProcessInfo.processInfo.environment["WALKCALC_PUSH_ENVIRONMENT"], !environment.isEmpty {
            return environment
        }
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private var stablePushDeviceId: String {
        let key = "walkcalc.pushDeviceId"
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private func interfaceIdiomName(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .phone:
            return "phone"
        case .pad:
            return "pad"
        case .tv:
            return "tv"
        case .carPlay:
            return "carPlay"
        case .mac:
            return "mac"
        case .vision:
            return "vision"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }

    var canLoadMoreGroups: Bool {
        groups.count < groupTotal
    }

    @discardableResult
    func refreshHome(search: String? = nil) async -> Bool {
        if isFixtureMode { return true }
        guard api.ledgerAPIEnabled else {
            resetLedgerState()
            return true
        }
        guard let token else { return false }
        let query = normalizedQuery(search)
        do {
            async let groupsResponse = api.groups(page: 1, pageSize: groupPageSize, search: optionalQuery(query), token: token)
            async let summaryResponse = api.homeSummary(token: token)
            let (response, summary) = try await (groupsResponse, summaryResponse)
            applyRefreshedToken(response)
            applyRefreshedToken(summary)
            if summary.success, let total = summary.data {
                totalBalanceMinor = total
            }
            if response.success {
                groupSearchQuery = query
                groups = mergedGroupSummaries(response.data ?? [])
                groupsPage = response.pagination?.page ?? 1
                groupTotal = response.pagination?.total ?? groups.count
                return true
            } else {
                recordFailure(operation: "refreshHome.groups", intent: .backgroundRefresh, disposition: .silent, response: response)
                return false
            }
        } catch {
            recordFailure(operation: "refreshHome", intent: .backgroundRefresh, disposition: .silent, error: error)
            return false
        }
    }

    func loadMoreGroups() async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
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
                recordFailure(operation: "loadMoreGroups", intent: .pagination, disposition: .silent, response: response)
            }
        } catch {
            recordFailure(operation: "loadMoreGroups", intent: .pagination, disposition: .silent, error: error)
        }
    }

    func group(id: String) -> WalkGroup? {
        groups.first(where: { $0.id == id })
    }

    func refreshGroup(_ id: String) async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
        guard let token else { return }
        do {
            async let groupResponse = api.group(code: id, token: token)
            async let recordsResponse = api.records(groupCode: id, page: 1, pageSize: recordPageSize, token: token)
            let (groupResult, recordResult) = try await (groupResponse, recordsResponse)
            applyRefreshedToken(groupResult)
            applyRefreshedToken(recordResult)
            if groupResult.success, let group = groupResult.data {
                replaceGroup(group)
                settlementSuggestionsByGroup[id] = nil
            }
            if recordResult.success {
                clearRecordCaches(for: id)
                recordsByGroup[id] = recordResult.data ?? []
                recordTotals[id] = recordResult.pagination?.total ?? recordResult.data?.count ?? 0
            }
            if !groupResult.success {
                recordFailure(operation: "refreshGroup.group", intent: .backgroundRefresh, disposition: .silent, response: groupResult)
            }
            if !recordResult.success {
                recordFailure(operation: "refreshGroup.records", intent: .backgroundRefresh, disposition: .silent, response: recordResult)
            }
        } catch {
            recordFailure(operation: "refreshGroup", intent: .backgroundRefresh, disposition: .silent, error: error)
        }
    }

    func refreshGroupBalances(_ id: String) async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
        guard let token else { return }
        do {
            let response = try await api.groupBalances(groupCode: id, token: token)
            applyRefreshedToken(response)
            if response.success, let members = response.data {
                replaceGroupBalances(groupId: id, members: members)
            } else {
                recordFailure(operation: "refreshGroupBalances", intent: .secondaryLoad, disposition: .silent, response: response)
            }
        } catch {
            recordFailure(operation: "refreshGroupBalances", intent: .secondaryLoad, disposition: .silent, error: error)
        }
    }

    func loadMoreRecords(groupId: String, search: String = "") async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
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
            } else {
                recordFailure(operation: "loadMoreRecords", intent: .pagination, disposition: .silent, response: response)
            }
        } catch {
            recordFailure(operation: "loadMoreRecords", intent: .pagination, disposition: .silent, error: error)
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

    func canLoadMoreRecords(groupId: String, search: String = "") -> Bool {
        let query = normalizedQuery(search)
        return cachedRecords(groupId: groupId, search: query).count < cachedRecordTotal(groupId: groupId, search: query)
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
        guard api.ledgerAPIEnabled else { return }
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
            } else {
                recordFailure(operation: "searchRecords", intent: .secondaryLoad, disposition: .silent, response: response)
            }
        } catch {
            recordFailure(operation: "searchRecords", intent: .secondaryLoad, disposition: .silent, error: error)
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

    func isLoadingMemberRecords(groupId: String, memberId: String) -> Bool {
        loadingRecordKeys.contains(memberRecordKey(groupId: groupId, memberId: memberId))
    }

    func canLoadMoreMemberRecords(groupId: String, memberId: String) -> Bool {
        memberRecords(groupId: groupId, memberId: memberId).count < memberRecordTotal(groupId: groupId, memberId: memberId)
    }

    func refreshMemberRecords(groupId: String, memberId: String) async {
        let key = memberRecordKey(groupId: groupId, memberId: memberId)
        if isFixtureMode {
            let matches = (recordsByGroup[groupId] ?? []).filter { recordIncludesParticipant($0, participantId: memberId) }
            memberRecordsByKey[key] = matches
            memberRecordTotalsByKey[key] = matches.count
            return
        }
        guard api.ledgerAPIEnabled else { return }
        guard let token else { return }
        guard !loadingRecordKeys.contains(key) else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        do {
            let response = try await api.participantRecords(groupCode: groupId, participantId: memberId, page: 1, pageSize: recordPageSize, token: token)
            applyRefreshedToken(response)
            if response.success {
                if let member = response.data?.member {
                    replaceMemberProjection(groupId: groupId, member: member)
                }
                let records = response.data?.records ?? []
                memberRecordsByKey[key] = records
                memberRecordTotalsByKey[key] = response.pagination?.total ?? records.count
            } else {
                recordFailure(operation: "refreshMemberRecords", intent: .secondaryLoad, disposition: .silent, response: response)
            }
        } catch {
            recordFailure(operation: "refreshMemberRecords", intent: .secondaryLoad, disposition: .silent, error: error)
        }
    }

    func loadMoreMemberRecords(groupId: String, memberId: String) async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
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
            let response = try await api.participantRecords(groupCode: groupId, participantId: memberId, page: page, pageSize: recordPageSize, token: token)
            applyRefreshedToken(response)
            if response.success {
                if let member = response.data?.member {
                    replaceMemberProjection(groupId: groupId, member: member)
                }
                memberRecordsByKey[key] = current + (response.data?.records ?? [])
                memberRecordTotalsByKey[key] = response.pagination?.total ?? total
            } else {
                recordFailure(operation: "loadMoreMemberRecords", intent: .pagination, disposition: .silent, response: response)
            }
        } catch {
            recordFailure(operation: "loadMoreMemberRecords", intent: .pagination, disposition: .silent, error: error)
        }
    }

    func createGroup(name: String) async -> Bool {
        await createGroupWithFeedback(name: name, users: [], tempUsers: []).success
    }

    func createGroup(name: String, users: [UserProfile], tempUsers: [String]) async -> Bool {
        await createGroupWithFeedback(name: name, users: users, tempUsers: tempUsers).success
    }

    func createGroupWithFeedback(name: String, users: [UserProfile], tempUsers: [String]) async -> StoreActionResult {
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
            return .success
        }
        return await withLoadingResult(operation: "createGroup") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.createGroup(name: name, token: token)
            applyRefreshedToken(response)
            if response.success, let groupId = response.data, !groupId.isEmpty {
                if !users.isEmpty {
                    let inviteResponse = try await api.invite(code: groupId, userIds: users.map(\.uuid), token: token)
                    applyRefreshedToken(inviteResponse)
                    guard inviteResponse.success else {
                        return actionFailure(operation: "createGroup.invite", response: inviteResponse)
                    }
                }
                for tempUser in tempUsers where !tempUser.isEmpty {
                    let tempUserResponse = try await api.addTempUser(code: groupId, name: tempUser, token: token)
                    applyRefreshedToken(tempUserResponse)
                    guard tempUserResponse.success else {
                        return actionFailure(operation: "createGroup.tempUser", response: tempUserResponse)
                    }
                }
            }
            await refreshHome()
            return response.success ? .success : actionFailure(operation: "createGroup", response: response)
        }
    }

    func joinGroup(code: String) async -> Bool {
        await joinGroupWithFeedback(code: code).success
    }

    func joinGroupWithFeedback(code: String) async -> JoinGroupResult {
        do {
            guard api.ledgerAPIEnabled else {
                return JoinGroupResult(success: false, message: nil)
            }
            guard let token else {
                return JoinGroupResult(success: false, message: L("Login to continue"))
            }
            let response = try await api.joinGroup(code: code, token: token)
            applyRefreshedToken(response)
            if response.success {
                await refreshHome()
            }
            return JoinGroupResult(success: response.success, message: response.message)
        } catch {
            recordFailure(operation: "joinGroup", intent: .userAction, disposition: .local, error: error)
            return JoinGroupResult(success: false, message: L("Network issues"))
        }
    }

    func archiveGroup(_ code: String) async -> Bool {
        await archiveGroupWithFeedback(code).success
    }

    func archiveGroupWithFeedback(_ code: String) async -> StoreActionResult {
        if isFixtureMode, let user {
            guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(nil) }
            if !groups[index].archivedUsers.contains(user.uuid) {
                groups[index].archivedUsers.append(user.uuid)
            }
            return .success
        }
        return await withLoadingResult(operation: "archiveGroup") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.archiveGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success ? .success : actionFailure(operation: "archiveGroup", response: response)
        }
    }

    func unarchiveGroup(_ code: String) async -> Bool {
        await unarchiveGroupWithFeedback(code).success
    }

    func unarchiveGroupWithFeedback(_ code: String) async -> StoreActionResult {
        if isFixtureMode, let user {
            guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(nil) }
            groups[index].archivedUsers.removeAll { $0 == user.uuid }
            return .success
        }
        return await withLoadingResult(operation: "unarchiveGroup") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.unarchiveGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success ? .success : actionFailure(operation: "unarchiveGroup", response: response)
        }
    }

    func deleteGroup(_ code: String) async -> Bool {
        await deleteGroupWithFeedback(code).success
    }

    func deleteGroupWithFeedback(_ code: String) async -> StoreActionResult {
        if isFixtureMode {
            groups.removeAll { $0.id == code }
            recordsByGroup[code] = nil
            recordTotals[code] = nil
            return .success
        }
        return await withLoadingResult(operation: "deleteGroup") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.deleteGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success ? .success : actionFailure(operation: "deleteGroup", response: response)
        }
    }

    func changeGroupName(_ code: String, name: String) async -> Bool {
        await changeGroupNameWithFeedback(code, name: name).success
    }

    func changeGroupNameWithFeedback(_ code: String, name: String) async -> StoreActionResult {
        if isFixtureMode {
            guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(nil) }
            groups[index].name = name
            groups[index].modifiedAt = Date().timeIntervalSince1970 * 1000
            return .success
        }
        return await withLoadingResult(operation: "changeGroupName") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.changeGroupName(code: code, name: name, token: token)
            applyRefreshedToken(response)
            await refreshGroup(code)
            return response.success ? .success : actionFailure(operation: "changeGroupName", response: response)
        }
    }

    func addMembers(groupId: String, users: [UserProfile], tempUsers: [String]) async -> Bool {
        await addMembersWithFeedback(groupId: groupId, users: users, tempUsers: tempUsers).success
    }

    func addMembersWithFeedback(groupId: String, users: [UserProfile], tempUsers: [String]) async -> StoreActionResult {
        if isFixtureMode {
            guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return .failure(nil) }
            for user in users where !groups[index].membersInfo.contains(where: { $0.uuid == user.uuid }) {
                groups[index].membersInfo.append(Member(uuid: user.uuid, name: user.name, avatar: user.avatar, debtMinor: "0", costMinor: "0"))
            }
            for tempUser in tempUsers where !tempUser.isEmpty {
                groups[index].tempUsers.append(Member(uuid: "temp-\(tempUser)-\(groups[index].tempUsers.count)", name: tempUser, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true))
            }
            return .success
        }
        return await withLoadingResult(operation: "addMembers") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            if !users.isEmpty {
                let response = try await api.invite(code: groupId, userIds: users.map(\.uuid), token: token)
                applyRefreshedToken(response)
                guard response.success else {
                    return actionFailure(operation: "addMembers.invite", response: response)
                }
            }
            for tempUser in tempUsers where !tempUser.isEmpty {
                let response = try await api.addTempUser(code: groupId, name: tempUser, token: token)
                applyRefreshedToken(response)
                guard response.success else {
                    return actionFailure(operation: "addMembers.tempUser", response: response)
                }
            }
            await refreshGroup(groupId)
            return .success
        }
    }

    func searchUsers(name: String) async -> [UserProfile] {
        if isFixtureMode {
            let names = ["Alexandra", "Christopher", "Noah", "Ivy", "Owen", "Tara", "June", "Keith", "Lin", "Ming", "Yan"]
            return names
                .filter { $0.localizedCaseInsensitiveContains(name) }
                .map { UserProfile(uuid: "fixture-\($0)", name: $0, avatar: "") }
        }
        guard api.ledgerAPIEnabled else { return [] }
        guard let token, !name.isEmpty else { return [] }
        do {
            let response = try await api.searchUsers(name: name, token: token)
            applyRefreshedToken(response)
            return response.data ?? []
        } catch {
            recordFailure(operation: "searchUsers", intent: .secondaryLoad, disposition: .silent, error: error)
            return []
        }
    }

    func addRecord(groupId: String, who: String, paid: String, forWhom: [String], type: String, text: String, long: String = "", lat: String = "", occurredAt: TimeInterval) async -> Bool {
        await addRecordWithFeedback(groupId: groupId, who: who, paid: paid, forWhom: forWhom, type: type, text: text, long: long, lat: lat, occurredAt: occurredAt).success
    }

    func addRecordWithFeedback(groupId: String, who: String, paid: String, forWhom: [String], type: String, text: String, long: String = "", lat: String = "", occurredAt: TimeInterval) async -> StoreActionResult {
        if isFixtureMode {
            guard let paidMinor = try? Money.parseDisplay(paid), Money.isPositive(paidMinor) else { return .failure(L("Enter a valid amount with up to 2 decimal places")) }
            let now = Date().timeIntervalSince1970 * 1000
            let record = WalkRecord(
                recordId: "fixture-record-\(Int(Date().timeIntervalSince1970 * 1000))",
                who: who,
                paidMinor: paidMinor,
                forWhom: forWhom,
                type: type,
                text: text,
                long: long,
                lat: lat,
                createdAt: now,
                occurredAt: occurredAt,
                modifiedAt: now,
                isDebtResolve: false
            )
            recordsByGroup[groupId, default: []].insert(record, at: 0)
            recordTotals[groupId] = recordsByGroup[groupId]?.count ?? 0
            return .success
        }
        return await withLoadingResult(operation: "addRecord") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            guard let paidMinor = try? Money.parseDisplay(paid), Money.isPositive(paidMinor) else { return .failure(L("Enter a valid amount with up to 2 decimal places")) }
            let response = try await api.addRecord(groupCode: groupId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, token: token, long: long, lat: lat, occurredAt: occurredAt)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            await refreshHome(search: groupSearchQuery)
            return response.success ? .success : actionFailure(operation: "addRecord", response: response)
        }
    }

    func editRecord(groupId: String, recordId: String, who: String, paid: String, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool = false) async -> Bool {
        await editRecordWithFeedback(groupId: groupId, recordId: recordId, who: who, paid: paid, forWhom: forWhom, type: type, text: text, occurredAt: occurredAt, isSettlement: isSettlement).success
    }

    func editRecordWithFeedback(groupId: String, recordId: String, who: String, paid: String, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool = false) async -> StoreActionResult {
        if isFixtureMode {
            guard let paidMinor = try? Money.parseDisplay(paid),
                  Money.isPositive(paidMinor),
                  let index = recordsByGroup[groupId]?.firstIndex(where: { $0.recordId == recordId }) else { return .failure(nil) }
            recordsByGroup[groupId]?[index].who = who
            recordsByGroup[groupId]?[index].paidMinor = paidMinor
            recordsByGroup[groupId]?[index].forWhom = forWhom
            recordsByGroup[groupId]?[index].type = type
            recordsByGroup[groupId]?[index].text = text
            recordsByGroup[groupId]?[index].occurredAt = occurredAt
            recordsByGroup[groupId]?[index].modifiedAt = Date().timeIntervalSince1970 * 1000
            return .success
        }
        return await withLoadingResult(operation: "editRecord") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            guard let paidMinor = try? Money.parseDisplay(paid), Money.isPositive(paidMinor) else { return .failure(L("Enter a valid amount with up to 2 decimal places")) }
            let response = try await api.updateRecord(groupCode: groupId, recordId: recordId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, token: token, occurredAt: occurredAt, isSettlement: isSettlement)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            await refreshHome(search: groupSearchQuery)
            return response.success ? .success : actionFailure(operation: "editRecord", response: response)
        }
    }

    func deleteRecord(groupId: String, recordId: String) async -> Bool {
        await deleteRecordWithFeedback(groupId: groupId, recordId: recordId).success
    }

    func deleteRecordWithFeedback(groupId: String, recordId: String) async -> StoreActionResult {
        if isFixtureMode {
            recordsByGroup[groupId]?.removeAll { $0.recordId == recordId }
            recordTotals[groupId] = recordsByGroup[groupId]?.count ?? 0
            clearRecordCaches(for: groupId)
            return .success
        }
        return await withLoadingResult(operation: "deleteRecord") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.dropRecord(groupCode: groupId, recordId: recordId, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            await refreshHome(search: groupSearchQuery)
            return response.success ? .success : actionFailure(operation: "deleteRecord", response: response)
        }
    }

    func resolveSingle(groupId: String, debt: ResolvedDebt) async -> Bool {
        await resolveSingleWithFeedback(groupId: groupId, debt: debt).success
    }

    func resolveSingleWithFeedback(groupId: String, debt: ResolvedDebt) async -> StoreActionResult {
        await withLoadingResult(operation: "resolveSingle") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.addSettlementRecord(
                groupCode: groupId,
                fromId: debt.from.uuid,
                toId: debt.to.uuid,
                amountMinor: debt.amountMinor,
                note: "resolve",
                token: token,
            )
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            await refreshHome(search: groupSearchQuery)
            return response.success ? .success : actionFailure(operation: "resolveSingle", response: response)
        }
    }

    func resolveAll(groupId: String, debts: [ResolvedDebt]) async -> Bool {
        await resolveAllWithFeedback(groupId: groupId, debts: debts).success
    }

    func resolveAllWithFeedback(groupId: String, debts: [ResolvedDebt]) async -> StoreActionResult {
        await withLoadingResult(operation: "resolveAll") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let token else { return .failure(L("Login to continue")) }
            let response = try await api.resolveDebts(groupCode: groupId, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            await refreshHome(search: groupSearchQuery)
            return response.success ? .success : actionFailure(operation: "resolveAll", response: response)
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
        if let cached = settlementSuggestionsByGroup[group.id] {
            return cached.compactMap { transfer in
                guard let from = group.allMembers.first(where: { $0.uuid == transfer.fromId }),
                      let to = group.allMembers.first(where: { $0.uuid == transfer.toId }) else {
                    return nil
                }
                return ResolvedDebt(from: from, to: to, amountMinor: transfer.amountMinor)
            }
        }
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

    func refreshSettlementSuggestion(groupId: String) async {
        if isFixtureMode { return }
        guard let token else { return }
        do {
            let response = try await api.settlementSuggestion(groupCode: groupId, token: token)
            applyRefreshedToken(response)
            if response.success {
                settlementSuggestionsByGroup[groupId] = (response.data ?? []).map {
                    SettlementTransfer(fromId: $0.fromId, toId: $0.toId, amountMinor: $0.amountMinor)
                }
            } else {
                recordFailure(operation: "refreshSettlementSuggestion", intent: .secondaryLoad, disposition: .silent, response: response)
            }
        } catch {
            recordFailure(operation: "refreshSettlementSuggestion", intent: .secondaryLoad, disposition: .silent, error: error)
        }
    }

    private func replaceGroup(_ group: WalkGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = mergedGroupSummary(group, existing: groups[index])
        } else {
            groups.append(group)
        }
    }

    private func replaceGroupBalances(groupId: String, members: [Member]) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].membersInfo = members.filter { !$0.isTemporary }
        groups[index].tempUsers = members.filter(\.isTemporary)
        groups[index].participantCount = members.count
    }

    private func replaceMemberProjection(groupId: String, member: Member) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        if member.isTemporary {
            if let memberIndex = groups[index].tempUsers.firstIndex(where: { $0.uuid == member.uuid }) {
                groups[index].tempUsers[memberIndex] = member
            }
        } else if let memberIndex = groups[index].membersInfo.firstIndex(where: { $0.uuid == member.uuid }) {
            groups[index].membersInfo[memberIndex] = member
        }
    }

    private func mergedGroupSummaries(_ summaries: [WalkGroup]) -> [WalkGroup] {
        summaries.map { summary in
            if let existing = groups.first(where: { $0.id == summary.id }) {
                return mergedGroupSummary(summary, existing: existing)
            }
            return summary
        }
    }

    private func mergedGroupSummary(_ incoming: WalkGroup, existing: WalkGroup) -> WalkGroup {
        var merged = incoming
        if incoming.allMembers.isEmpty, !existing.allMembers.isEmpty {
            merged.membersInfo = existing.membersInfo
            merged.tempUsers = existing.tempUsers
        }
        if merged.participantPreview.isEmpty {
            merged.participantPreview = existing.participantPreview
        }
        if merged.participantCount == 0 {
            merged.participantCount = max(existing.participantCount, merged.allMembers.count, merged.participantPreview.count)
        }
        return merged
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

    private func withLoadingResult(operation: String, _ action: () async throws -> StoreActionResult) async -> StoreActionResult {
        do {
            let result = try await action()
            if !result.success {
                networkFeedbackLogger.info("Action failure operation=\(operation, privacy: .public) disposition=\(FeedbackDisposition.local.rawValue, privacy: .public)")
            }
            return result
        } catch {
            recordFailure(operation: operation, intent: .userAction, disposition: .local, error: error)
            return .failure(nil)
        }
    }

    private func actionFailure<T>(operation: String, response: APIEnvelope<T>) -> StoreActionResult {
        recordFailure(operation: operation, intent: .userAction, disposition: .local, response: response)
        return .failure(response.messageWithLimitDetail)
    }

    private func recordFailure<T>(operation: String, intent: NetworkOperationIntent, disposition: FeedbackDisposition, response: APIEnvelope<T>) {
        let kind = response.failureKind?.rawValue ?? APIFailureKind.serverEnvelope.rawValue
        let status = response.statusCode ?? 0
        networkFeedbackLogger.info("Network failure operation=\(operation, privacy: .public) intent=\(intent.rawValue, privacy: .public) disposition=\(disposition.rawValue, privacy: .public) kind=\(kind, privacy: .public) status=\(status, privacy: .public)")
    }

    private func recordFailure(operation: String, intent: NetworkOperationIntent, disposition: FeedbackDisposition, error: Error) {
        let clientError = error as? APIClientError
        let kind = clientError?.kind.rawValue ?? APIFailureKind.transport.rawValue
        let status = clientError?.statusCode ?? 0
        networkFeedbackLogger.info("Network failure operation=\(operation, privacy: .public) intent=\(intent.rawValue, privacy: .public) disposition=\(disposition.rawValue, privacy: .public) kind=\(kind, privacy: .public) status=\(status, privacy: .public)")
    }
}

private extension APIEnvelope {
    var messageWithLimitDetail: String? {
        guard let message else { return nil }
        guard let limit = intValue(errorData?["limit"]),
              let count = intValue(errorData?["nonZeroParticipantCount"]) else {
            return message
        }
        return "\(message) (\(count)/\(limit))"
    }

    func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }
}
