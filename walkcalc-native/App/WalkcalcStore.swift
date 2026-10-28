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
    let createdGroupId: String?

    static var success: StoreActionResult {
        StoreActionResult(success: true, message: nil, createdGroupId: nil)
    }

    static func success(createdGroupId: String) -> StoreActionResult {
        StoreActionResult(success: true, message: nil, createdGroupId: createdGroupId)
    }

    static func failure(_ message: String?) -> StoreActionResult {
        StoreActionResult(success: false, message: message, createdGroupId: nil)
    }
}

struct StoreAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum StartupRoute: Equatable {
    case resolving
    case loginRequired
    case authenticated
}

private enum NetworkOperationIntent: String {
    case bootstrapAuth
    case foregroundRefresh
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

private enum HomeRefreshResult {
    case success
    case recoverableFailure
    case unrecoverableAuthFailure

    var succeeded: Bool {
        switch self {
        case .success:
            return true
        case .recoverableFailure, .unrecoverableAuthFailure:
            return false
        }
    }
}

@MainActor
final class WalkcalcStore: ObservableObject {
    @Published var token: String?
    @Published var user: UserProfile?
    @Published var groups: [WalkGroup] = []
    @Published var recordsByGroup: [String: [WalkRecord]] = [:]
    @Published var recordTotals: [String: Int] = [:]
    @Published var totalBalanceMinor: MoneyMinor = "0"
    @Published private(set) var totalBalancesByCurrency: [CurrencyBalanceSummary] = []
    @Published private(set) var groupTotal = 0
    @Published private(set) var isLoadingMoreGroups = false
    @Published private(set) var needsGroupOrderRefresh = false
    @Published private(set) var pendingGroupPins: [String: UUID] = [:]
    @Published private(set) var completedGroupPinUpdates = 0
    @Published var isBootstrapping = true
    @Published private(set) var startupRoute: StartupRoute = .resolving
    @Published private(set) var isSigningIn = false
    @Published var urgentAlert: StoreAlert?
    @Published var selectedTheme: AppTheme = AppTheme.load()
    @Published var isFixtureMode = false
    @Published private var recordSearchResultsByKey: [String: [WalkRecord]] = [:]
    @Published private var recordSearchTotalsByKey: [String: Int] = [:]
    @Published private var memberRecordsByKey: [String: [WalkRecord]] = [:]
    @Published private var memberRecordTotalsByKey: [String: Int] = [:]
    @Published private var settlementSuggestionsByGroup: [String: [SettlementTransfer]] = [:]
    @Published private var settlementSuggestionReadyGroupIds: Set<String> = []
    private var groupContentRefreshTasks: [String: Task<Void, Never>] = [:]
    private struct GroupContentQuery: Equatable {
        var text: String
        var filters: GroupRecordFilters
    }
    private var groupContentRefreshQueries: [String: GroupContentQuery] = [:]
    private var groupContentRefreshIDs: [String: UUID] = [:]
    private var groupPinWaiters: [CheckedContinuation<Void, Never>] = []
    @Published private var loadingRecordKeys: Set<String> = []
    @Published private(set) var preferredLedgerSource: LedgerSourceKind = .remote
    @Published private var groupSourceById: [String: LedgerSourceMetadata] = [:]

    let api = APIClient()
    private var ledgerRepository: LedgerRepository
    private let localOwnerId: String
    private let groupPageSize = 20
    @Published private var recordFiltersByScope: [String: GroupRecordFilters] = [:]
    private var recordCacheRevisions: [String: Int] = [:]
    private let recordPageSize = 10
    private var groupsPage = 0
    private var groupListRevision = 0
    private var groupSearchQuery = ""
    private var apnsProviderToken = UserDefaults.standard.string(forKey: "walkcalc.apnsProviderToken")
    private var pushDeviceRegistrationTask: Task<Void, Never>?
    private var isHandlingForegroundActivation = false
    private var cancellables: Set<AnyCancellable> = []
    private let networkFeedbackLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "walkcalc-native", category: "NetworkFeedback")

    var primaryColor: Color {
        selectedTheme.accent
    }

    var primaryUIColor: UIColor {
        selectedTheme.accentUIColor
    }

    var isLoggedIn: Bool {
        token != nil
    }

    init(ledgerRepository: LedgerRepository? = nil, localOwnerId: String? = nil) {
        self.localOwnerId = localOwnerId ?? Self.loadLocalOwnerId()
        self.ledgerRepository = ledgerRepository ?? LedgerRepository(
            remoteSource: RemoteLedgerDataSource(api: api),
            localSource: SwiftDataLedgerDataSource.production()
        )
        token = UserDefaults.standard.string(forKey: "walkcalc.token")
        if token == nil {
            preferredLedgerSource = .local
        } else if let data = UserDefaults.standard.data(forKey: "walkcalc.cachedUser") {
            user = try? JSONDecoder().decode(UserProfile.self, from: data)
        }
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
        applyAuthSessionSimulationSeedIfRequested()
        if let fixture = WalkcalcDebugFixture.current {
            applyDebugFixture(fixture)
        }
        #endif
    }

    func bootstrap() async {
        if isFixtureMode {
            finishStartup(.authenticated)
            return
        }
        isBootstrapping = true
        startupRoute = .resolving
        defer { isBootstrapping = false }
        guard let token else {
            preferredLedgerSource = .local
            _ = await refreshHome()
            startupRoute = .authenticated
            return
        }
        preferredLedgerSource = .remote
        async let userProfile = fetchUser(token: token)
        async let homeBootstrap = bootstrapHomeIfNeeded(token: token)
        let signedInUser = await userProfile
        let homeBootstrapResult = await homeBootstrap
        guard self.token != nil, homeBootstrapResult != .unrecoverableAuthFailure else { return }
        if let signedInUser { cacheUser(signedInUser) }
        await registerPushDeviceIfPossible(reason: "app_open")
        startupRoute = .authenticated
    }

    func prepareNetworkAccessForStartup() async {
        guard !isFixtureMode else { return }
        await api.warmUpNetworkAccess()
    }

    var shouldSkipNotificationPermissionRequest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["WALKCALC_SKIP_NOTIFICATION_PERMISSION"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--simulate-auth-session-seed")
        #else
        false
        #endif
    }

    func handleForegroundActivation() async {
        guard !isFixtureMode else { return }
        guard startupRoute == .authenticated else { return }
        guard let token else { return }
        guard !isHandlingForegroundActivation else { return }

        isHandlingForegroundActivation = true
        defer { isHandlingForegroundActivation = false }

        do {
            let response = try await api.userInfo(token: token)
            applyRefreshedToken(response)
            if response.success, let data = response.data {
                cacheUser(data)
            } else {
                recordFailure(operation: "foreground.userInfo", intent: .foregroundRefresh, disposition: .silent, response: response)
                return
            }
        } catch {
            recordFailure(operation: "foreground.userInfo", intent: .foregroundRefresh, disposition: .silent, error: error)
            return
        }

        await registerPushDeviceIfPossible(reason: "foreground")
        if api.ledgerAPIEnabled {
            _ = await refreshHome()
        }
    }

    func reconcileSessionAfterProfileDismiss() async {
        guard !isFixtureMode else { return }
        guard let token else { return }

        do {
            let response = try await api.userInfo(token: token)
            applyRefreshedToken(response)
            guard response.success, let data = response.data else {
                recordFailure(operation: "profileDismiss.userInfo", intent: .foregroundRefresh, disposition: .silent, response: response)
                return
            }
            cacheUser(data)
        } catch {
            recordFailure(operation: "profileDismiss.userInfo", intent: .foregroundRefresh, disposition: .silent, error: error)
        }
    }

    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
        theme.persist()
    }

    func setThemeColor(_ id: String) {
        setTheme(AppTheme(rawValue: id) ?? AppTheme.theme(forLegacyValue: id))
    }

    func setPreferredLedgerSource(_ source: LedgerSourceKind) {
        preferredLedgerSource = source
    }

    func signIn(token: String) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        await completeSignIn(token: token)
    }

    func signInWithApple(identityToken: String, authorizationCode: String?, fullName: String?, nonce: String?) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let response = try await api.signInWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName,
                nonce: nonce
            )
            guard response.success,
                  let session = response.data,
                  !session.accessToken.isEmpty else {
                networkFeedbackLogger.notice("Apple sign-in rejected by server")
                return
            }
            await completeSignIn(token: session.accessToken, prefetchedUser: session.user)
        } catch {
            recordFailure(operation: "appleSignIn", intent: .bootstrapAuth, disposition: .local, error: error)
        }
    }

    private func completeSignIn(token: String, prefetchedUser: UserProfile? = nil) async {
        if self.token != token {
            user = nil
            UserDefaults.standard.removeObject(forKey: "walkcalc.cachedUser")
        }
        self.token = token
        preferredLedgerSource = .remote
        UserDefaults.standard.set(token, forKey: "walkcalc.token")

        let resolvedUser: UserProfile?
        if let prefetchedUser, !prefetchedUser.uuid.isEmpty {
            resolvedUser = prefetchedUser
        } else {
            resolvedUser = await fetchUser(token: token)
        }

        guard self.token != nil else { return }
        if let signedInUser = resolvedUser { cacheUser(signedInUser) }
        await registerPushDeviceIfPossible(reason: "sign_in")
        if await bootstrapHomeIfNeeded(token: token) == .unrecoverableAuthFailure {
            return
        }
        startupRoute = .authenticated
    }

    func logout() {
        token = nil
        user = nil
        resetLedgerState()
        isSigningIn = false
        preferredLedgerSource = .local
        startupRoute = .authenticated
        NativeAuthSession.clearAuthCookies(baseURL: api.baseURL, webBaseURL: api.webBaseURL)
        UserDefaults.standard.removeObject(forKey: "walkcalc.token")
        UserDefaults.standard.removeObject(forKey: "walkcalc.cachedUser")
        Task { @MainActor in
            _ = await refreshHome()
        }
    }

    func finishStartup(_ route: StartupRoute) {
        startupRoute = route
        isBootstrapping = false
    }

    private func resetLedgerState() {
        pendingGroupPins = [:]
        resumeGroupPinWaiters()
        for task in groupContentRefreshTasks.values { task.cancel() }
        groupContentRefreshTasks = [:]
        groupContentRefreshQueries = [:]
        groupContentRefreshIDs = [:]
        groupListRevision += 1
        groups = []
        recordsByGroup = [:]
        recordTotals = [:]
        groupTotal = 0
        needsGroupOrderRefresh = false
        totalBalanceMinor = "0"
        totalBalancesByCurrency = []
        groupsPage = 0
        groupSearchQuery = ""
        recordSearchResultsByKey = [:]
        recordSearchTotalsByKey = [:]
        memberRecordsByKey = [:]
        memberRecordTotalsByKey = [:]
        settlementSuggestionsByGroup = [:]
        settlementSuggestionReadyGroupIds = []
        groupSourceById = [:]
    }

    func loadUser(token: String) async {
        if let profile = await fetchUser(token: token), self.token != nil {
            cacheUser(profile)
        }
    }

    private func cacheUser(_ profile: UserProfile) {
        user = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "walkcalc.cachedUser")
        }
    }

    private func fetchUser(token: String) async -> UserProfile? {
        do {
            let response = try await api.userInfo(token: token)
            applyRefreshedToken(response)
            if response.success, let data = response.data {
                return data
            } else {
                recordFailure(operation: "fetchUser", intent: .bootstrapAuth, disposition: .silent, response: response)
                return nil
            }
        } catch {
            recordFailure(operation: "fetchUser", intent: .bootstrapAuth, disposition: .silent, error: error)
            return nil
        }
    }

    func requestNotificationPermissionIfNeeded() async {
        if isFixtureMode { return }
        if shouldSkipNotificationPermissionRequest {
            return
        }
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
            do {
                let response = try await api.registerPushDevice(
                    token: token,
                    payload: pushDeviceRegistrationPayload(providerToken: providerToken, reason: reason)
                )
                await MainActor.run {
                    self.applyRefreshedToken(response)
                }
            } catch {
                await MainActor.run {
                    _ = self.recordFailure(operation: "registerPushDevice", intent: .backgroundRefresh, disposition: .silent, error: error)
                }
            }
        }

        await pushDeviceRegistrationTask?.value
    }

    private func pushDeviceRegistrationPayload(providerToken: String, reason: String) -> [String: Any] {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let device = UIDevice.current
        let environment = pushEnvironment
        return [
            "appId": ProcessInfo.processInfo.environment["WALKCALC_PUSH_APP_ID"] ?? "walkcalc-ios",
            "platform": "ios",
            "providerToken": providerToken,
            "environment": environment,
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
                "interfaceIdiom": interfaceIdiomName(device.userInterfaceIdiom),
                "pushEnvironment": environment
            ]
        ]
    }

    private var pushEnvironment: String {
        if let environment = ProcessInfo.processInfo.environment["WALKCALC_PUSH_ENVIRONMENT"], !environment.isEmpty {
            return environment
        }
        return signedAPNsEnvironment
    }

    private var signedAPNsEnvironment: String {
        if let value = embeddedProvisioningAPNsEnvironment {
            return value
        }

        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private var embeddedProvisioningAPNsEnvironment: String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }

        let profile = String(decoding: data, as: UTF8.self)
        guard let keyRange = profile.range(of: "<key>aps-environment</key>") else {
            return nil
        }

        let remainder = profile[keyRange.upperBound...]
        guard let valueStart = remainder.range(of: "<string>"),
              let valueEnd = remainder[valueStart.upperBound...].range(of: "</string>")
        else { return nil }

        let value = remainder[valueStart.upperBound..<valueEnd.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "development":
            return "sandbox"
        case "production":
            return "production"
        default:
            return nil
        }
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
        await waitForPendingGroupPins()
        guard !Task.isCancelled else { return false }
        if isFixtureMode { return true }
        if preferredLedgerSource == .remote, let token {
            return await refreshCombinedHome(remoteContext: remoteLedgerContext(token: token), search: search).succeeded
        }
        return await refreshHome(context: localLedgerContext(), search: search).succeeded
    }

    private func bootstrapHomeIfNeeded(token: String) async -> HomeRefreshResult {
        if isFixtureMode { return .success }
        guard api.ledgerAPIEnabled else {
            resetLedgerState()
            return .success
        }
        return await refreshCombinedHome(remoteContext: remoteLedgerContext(token: token))
    }

    private func refreshCombinedHome(remoteContext: LedgerSessionContext, search: String? = nil) async -> HomeRefreshResult {
        if isFixtureMode { return .success }
        guard api.ledgerAPIEnabled else {
            resetLedgerState()
            return .success
        }
        groupListRevision += 1
        let revision = groupListRevision
        let query = normalizedQuery(search)
        let remoteResult = await ledgerRepository.home(
            page: 1,
            pageSize: groupPageSize,
            search: optionalQuery(query),
            context: remoteContext
        )
        let localResult = await ledgerRepository.home(
            page: 1,
            pageSize: 10_000,
            search: optionalQuery(query),
            context: localLedgerContext()
        )

        guard revision == groupListRevision else { return .recoverableFailure }
        switch remoteResult {
        case .success(let remoteSnapshot):
            applyRefreshedToken(remoteSnapshot.refreshedToken)
            trackSource(remoteSnapshot.source, for: remoteSnapshot.groups)
            var combinedGroups = remoteSnapshot.groups
            var combinedTotalBalance = remoteSnapshot.totalBalanceMinor ?? "0"
            var combinedCurrencyBalances = resolvedCurrencyBalances(from: remoteSnapshot)
            var localTotal = 0
            if case .success(let localSnapshot) = localResult {
                trackSource(localSnapshot.source, for: localSnapshot.groups)
                combinedGroups.append(contentsOf: localSnapshot.groups)
                combinedTotalBalance = Money.add(combinedTotalBalance, localSnapshot.totalBalanceMinor ?? "0")
                combinedCurrencyBalances = mergedCurrencyBalances(
                    combinedCurrencyBalances,
                    resolvedCurrencyBalances(from: localSnapshot)
                )
                localTotal = localSnapshot.groupPagination?.total ?? localSnapshot.groups.count
            } else if case .failure(let failure) = localResult {
                recordFailure(operation: "refreshHome.local", intent: .backgroundRefresh, disposition: .silent, failure: failure)
            }
            groupSearchQuery = query
            totalBalanceMinor = combinedTotalBalance
            totalBalancesByCurrency = combinedCurrencyBalances
            groups = mergedGroupSummaries(mergingLocalGroupRows(combinedGroups))
            needsGroupOrderRefresh = false
            groupsPage = remoteSnapshot.groupPagination?.page ?? 1
            groupTotal = (remoteSnapshot.groupPagination?.total ?? remoteSnapshot.groups.count) + localTotal
            return .success
        case .failure(let failure):
            let authFailure = recordFailure(operation: "refreshHome", intent: .backgroundRefresh, disposition: .silent, failure: failure)
            if authFailure {
                return .unrecoverableAuthFailure
            }
            if groups.isEmpty, case .success(let localSnapshot) = localResult {
                trackSource(localSnapshot.source, for: localSnapshot.groups)
                groupSearchQuery = query
                totalBalanceMinor = localSnapshot.totalBalanceMinor ?? "0"
                totalBalancesByCurrency = resolvedCurrencyBalances(from: localSnapshot)
                groups = mergedGroupSummaries(localSnapshot.groups)
                groupsPage = 1
                groupTotal = localSnapshot.groupPagination?.total ?? localSnapshot.groups.count
            }
            return .recoverableFailure
        }
    }

    private func refreshHome(context: LedgerSessionContext, search: String? = nil) async -> HomeRefreshResult {
        if isFixtureMode { return .success }
        guard api.ledgerAPIEnabled else {
            resetLedgerState()
            return .success
        }
        groupListRevision += 1
        let revision = groupListRevision
        let query = normalizedQuery(search)
        let result = await ledgerRepository.home(
            page: 1,
            pageSize: groupPageSize,
            search: optionalQuery(query),
            context: context
        )
        guard revision == groupListRevision else { return .recoverableFailure }
        switch result {
        case .success(let snapshot):
            applyRefreshedToken(snapshot.refreshedToken)
            trackSource(snapshot.source, for: snapshot.groups)
            if let total = snapshot.totalBalanceMinor {
                totalBalanceMinor = total
            }
            totalBalancesByCurrency = resolvedCurrencyBalances(from: snapshot)
            groupSearchQuery = query
            groups = mergedGroupSummaries(snapshot.groups)
            needsGroupOrderRefresh = false
            groupsPage = snapshot.groupPagination?.page ?? 1
            groupTotal = snapshot.groupPagination?.total ?? groups.count
            return .success
        case .failure(let failure):
            let authFailure = recordFailure(operation: "refreshHome", intent: .backgroundRefresh, disposition: .silent, failure: failure)
            return authFailure ? .unrecoverableAuthFailure : .recoverableFailure
        }
    }

    func loadMoreGroups() async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
        guard let context = homeLedgerContext(), canLoadMoreGroups, !isLoadingMoreGroups else { return }
        if context.preferredSource == .local, token != nil {
            return
        }
        guard !needsGroupOrderRefresh else { return }
        let revision = groupListRevision
        isLoadingMoreGroups = true
        defer { isLoadingMoreGroups = false }
        let result = await ledgerRepository.groups(
            page: groupsPage + 1,
            pageSize: groupPageSize,
            search: optionalQuery(groupSearchQuery),
            context: context
        )
        guard revision == groupListRevision else { return }
        switch result {
        case .success(let page):
            applyRefreshedToken(page.refreshedToken)
            trackSource(page.source, for: page.items)
            appendGroups(page.items)
            groupsPage = page.pagination?.page ?? groupsPage + 1
            if context.preferredSource == .remote {
                let localTotal = groups.filter { isLocalLedgerGroup($0.id) }.count
                groupTotal = (page.pagination?.total ?? groupTotal) + localTotal
            } else {
                groupTotal = page.pagination?.total ?? groupTotal
            }
        case .failure(let failure):
            recordFailure(operation: "loadMoreGroups", intent: .pagination, disposition: .silent, failure: failure)
        }
    }

    func isGroupPinned(_ groupId: String) -> Bool {
        group(id: groupId)?.isPinned ?? false
    }

    func pinnedGroups(in availableGroups: [WalkGroup]) -> [WalkGroup] {
        // The data source already returns pin order before pagination.
        availableGroups.filter(\.isPinned)
    }

    private func waitForPendingGroupPins() async {
        while !pendingGroupPins.isEmpty {
            await withCheckedContinuation { groupPinWaiters.append($0) }
        }
    }

    private func resumeGroupPinWaiters() {
        guard pendingGroupPins.isEmpty else { return }
        let waiters = groupPinWaiters
        groupPinWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func setGroupPinned(_ pinned: Bool, groupId: String) async -> StoreActionResult {
        guard pendingGroupPins[groupId] == nil,
              let group = group(id: groupId) else { return .failure(nil) }
        let previousPin = group.pinnedAt
        let nextTime = max(Date().timeIntervalSince1970 * 1000, (groups.compactMap(\.pinnedAt).max() ?? 0) + 1)
        let operation = UUID()
        pendingGroupPins[groupId] = operation
        groupListRevision += 1
        needsGroupOrderRefresh = true
        // Both entry points render this shared optimistic state immediately.
        applyGroupPin(pinned ? (previousPin ?? nextTime) : nil, groupId: groupId)
        defer {
            if pendingGroupPins[groupId] == operation {
                groupListRevision += 1
                pendingGroupPins[groupId] = nil
                resumeGroupPinWaiters()
                completedGroupPinUpdates += 1
            }
        }
        if isFixtureMode { return .success }
        let result = await ledgerRepository.pinGroup(code: groupId, isPinned: pinned, context: context(for: groupId))
        // A sign-out/reset must not let an old response change the new session.
        guard pendingGroupPins[groupId] == operation else { return .failure(nil) }
        switch result {
        case .success(let response):
            guard let state = response.value else {
                applyGroupPin(previousPin, groupId: groupId)
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            applyGroupPin(state.pinnedAt, groupId: groupId)
            return .success
        case .failure(let failure):
            applyGroupPin(previousPin, groupId: groupId)
            return actionFailure(operation: "pinGroup", failure: failure)
        }
    }

    private func applyGroupPin(_ pinnedAt: TimeInterval?, groupId: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        var updated = groups.remove(at: index)
        updated.pinnedAt = pinnedAt
        // Move only the affected row; retain the server order of all other rows.
        let destination = groups.firstIndex { WalkGroup.homePrecedes(updated, $0) } ?? groups.endIndex
        groups.insert(updated, at: destination)
    }

    func group(id: String) -> WalkGroup? {
        groups.first(where: { $0.id == id })
    }

    func preferredRecordCurrencyCode(for groupId: String) -> String {
        let key = recordCurrencyPreferenceKey(groupId)
        if let stored = UserDefaults.standard.string(forKey: key)?.uppercased(),
           CurrencyCatalog.currencies.contains(where: { $0.code == stored }) {
            return stored
        }
        return CurrencyCatalog.normalizedCode(group(id: groupId)?.currencyCode)
    }

    func rememberRecordCurrencyCode(_ currencyCode: String, for groupId: String) {
        UserDefaults.standard.set(
            CurrencyCatalog.normalizedCode(currencyCode),
            forKey: recordCurrencyPreferenceKey(groupId)
        )
    }

    /// Use the same group-scoped projections as its Total Balance card.
    /// No record scanning or cross-group currency history is needed.
    func recentlyUsedCurrencyCodes(for groupId: String?, including selectedCode: String) -> Set<String> {
        var codes: Set<String> = [CurrencyCatalog.normalizedCode(selectedCode)]
        guard let groupId, let group = group(id: groupId) else { return codes }
        codes.insert(CurrencyCatalog.normalizedCode(group.currencyCode))
        let currentMember = group.allMembers.first { $0.uuid == currentParticipantID(for: group) }
        let projections = group.hasCurrentUserBalanceSummary
            ? group.currentUserCurrencyBalances
            : currentMember?.currencyBalances ?? []
        codes.formUnion(projections.map(\.currencyCode))
        return codes
    }

    private func recordFilterPreferenceKey(_ groupId: String) -> String {
        let owner = isLocalLedgerGroup(groupId) ? localOwner.uuid : user?.uuid ?? "anonymous"
        return "walkcalc.recordFilters.\(owner).\(groupId)"
    }

    func recordFilters(for groupId: String) -> GroupRecordFilters {
        let key = recordFilterPreferenceKey(groupId)
        if let cached = recordFiltersByScope[key] { return cached }
        guard let data = UserDefaults.standard.data(forKey: key),
              let filters = try? JSONDecoder().decode(GroupRecordFilters.self, from: data) else { return GroupRecordFilters() }
        return filters
    }

    func setRecordFilters(_ filters: GroupRecordFilters, for groupId: String) {
        guard filters != recordFilters(for: groupId) else { return }
        let key = recordFilterPreferenceKey(groupId)
        UserDefaults.standard.set(try? JSONEncoder().encode(filters), forKey: key)
        recordFiltersByScope[key] = filters
        groupContentRefreshTasks[groupId]?.cancel()
        groupContentRefreshTasks[groupId] = nil
        groupContentRefreshQueries[groupId] = nil
        groupContentRefreshIDs[groupId] = nil
        clearRecordCaches(for: groupId)
        if !isFixtureMode {
            recordsByGroup[groupId] = nil
            recordTotals[groupId] = nil
        }
    }

    func filteredCurrencyBalances(_ balances: [CurrencyBalanceSummary], groupId: String) -> [CurrencyBalanceSummary] {
        let codes = recordFilters(for: groupId).currencyCodes
        guard !codes.isEmpty else { return balances }
        // A selected currency with no personal activity still has a labeled zero balance.
        return codes.sorted().map { code in
            balances.first { $0.currencyCode == code }
                ?? CurrencyBalanceSummary(currencyCode: code, totalBalanceMinor: "0")
        }
    }

    func visibleResolvedDebts(for group: WalkGroup) -> [ResolvedDebt] {
        resolvedDebts(for: group).filter { recordFilters(for: group.id).includesCurrency($0.currencyCode) }
    }

    func preloadGroupContent(_ id: String, search: String = "") {
        let query = GroupContentQuery(text: normalizedQuery(search), filters: recordFilters(for: id))
        if groupContentRefreshTasks[id] != nil {
            guard groupContentRefreshQueries[id] != query else { return }
            groupContentRefreshTasks[id]?.cancel()
        }
        let refreshID = UUID()
        groupContentRefreshQueries[id] = query
        groupContentRefreshIDs[id] = refreshID
        groupContentRefreshTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if groupContentRefreshIDs[id] == refreshID {
                    groupContentRefreshTasks[id] = nil
                    groupContentRefreshQueries[id] = nil
                    groupContentRefreshIDs[id] = nil
                }
            }
            async let groupRefresh: Void = refreshGroup(id, search: query.text)
            async let balancesRefresh: Void = refreshGroupBalances(id)
            async let settlementRefresh: Void = refreshSettlementSuggestion(groupId: id)
            _ = await (groupRefresh, balancesRefresh, settlementRefresh)
        }
    }

    func refreshGroupContent(_ id: String, search: String = "") async {
        preloadGroupContent(id, search: search)
        let task = groupContentRefreshTasks[id]
        await task?.value
    }

    private func refreshGroupAfterLedgerMutation(_ id: String) async {
        async let groupRefresh: Void = refreshGroup(id)
        async let balancesRefresh: Void = refreshGroupBalances(id)
        _ = await (groupRefresh, balancesRefresh)
        await refreshSettlementSuggestion(groupId: id)

        _ = await refreshHome(search: groupSearchQuery)
    }

    func refreshGroup(_ id: String, search: String = "") async {
        let query = normalizedQuery(search)
        if isFixtureMode {
            if !query.isEmpty { await searchRecords(groupId: id, query: query) }
            return
        }
        guard api.ledgerAPIEnabled else { return }
        let context = context(for: id)
        let filters = recordFilters(for: id)
        let pinRevision = groupListRevision
        let result = await ledgerRepository.groupDetail(groupId: id, recordPageSize: recordPageSize, recordSearch: recordSearchRequest(for: query, groupId: id), context: context)
        guard !Task.isCancelled, filters == recordFilters(for: id) else { return }
        switch result {
        case .success(let snapshot):
            applyRefreshedToken(snapshot.refreshedToken)
            if let group = snapshot.group {
                trackSource(snapshot.source, for: group)
            }
            if var group = snapshot.group {
                // A detail response started before a pin write must not undo
                // its acknowledged state after the optimistic marker clears.
                if pinRevision != groupListRevision, let current = self.group(id: id) {
                    group.pinnedAt = current.pinnedAt
                }
                replaceGroup(group)
            }
            clearRecordCaches(for: id)
            if query.isEmpty {
                recordsByGroup[id] = snapshot.records
                recordTotals[id] = snapshot.recordPagination?.total ?? snapshot.records.count
            } else {
                let key = recordListKey(groupId: id, search: query)
                recordSearchResultsByKey[key] = snapshot.records
                recordSearchTotalsByKey[key] = snapshot.recordPagination?.total ?? snapshot.records.count
            }
        case .failure(let failure):
            recordFailure(operation: "refreshGroup", intent: .backgroundRefresh, disposition: .silent, failure: failure)
        }
    }

    func refreshGroupBalances(_ id: String) async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
        let result = await ledgerRepository.groupBalances(groupId: id, context: context(for: id))
        switch result {
        case .success(let response):
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: id)
            if let members = response.value {
                replaceGroupBalances(groupId: id, members: members)
            }
        case .failure(let failure):
            recordFailure(operation: "refreshGroupBalances", intent: .secondaryLoad, disposition: .silent, failure: failure)
        }
    }

    func loadMoreRecords(groupId: String, search: String = "") async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
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
        let result = await ledgerRepository.records(
            groupId: groupId,
            page: page,
            pageSize: recordPageSize,
            search: recordSearchRequest(for: query, groupId: groupId),
            context: context(for: groupId)
        )
        guard !Task.isCancelled, key == recordListKey(groupId: groupId, search: query) else { return }
        switch result {
        case .success(let page):
            applyRefreshedToken(page.refreshedToken)
            trackSource(page.source, forGroupId: groupId)
            if query.isEmpty {
                recordsByGroup[groupId] = current + page.items
                recordTotals[groupId] = page.pagination?.total ?? total
            } else {
                recordSearchResultsByKey[key] = current + page.items
                recordSearchTotalsByKey[key] = page.pagination?.total ?? total
            }
        case .failure(let failure):
            recordFailure(operation: "loadMoreRecords", intent: .pagination, disposition: .silent, failure: failure)
        }
    }

    func records(groupId: String, search: String = "") -> [WalkRecord] {
        let query = normalizedQuery(search)
        guard !query.isEmpty else {
            return (recordsByGroup[groupId] ?? []).filter { recordSearchRequest(for: "", groupId: groupId)?.matches($0, defaultCurrency: group(id: groupId)?.currencyCode) ?? true }
        }
        let key = recordListKey(groupId: groupId, search: query)
        let localMatches = localSearchMatches(groupId: groupId, query: query)
        if let remote = recordSearchResultsByKey[key] {
            return remote
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

    func searchRecordsIfNeeded(groupId: String, query: String) async {
        guard !hasLoadedSearchRecords(groupId: groupId, search: query) else { return }
        await searchRecords(groupId: groupId, query: query)
    }

    func searchRecords(groupId: String, query rawQuery: String) async {
        let query = normalizedQuery(rawQuery)
        guard !query.isEmpty else { return }
        let key = recordListKey(groupId: groupId, search: query)
        if isFixtureMode {
            let matches = localSearchMatches(groupId: groupId, query: query)
            recordSearchResultsByKey[key] = matches
            recordSearchTotalsByKey[key] = matches.count
            return
        }
        guard api.ledgerAPIEnabled else { return }
        guard !loadingRecordKeys.contains(key) else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        let result = await ledgerRepository.records(
            groupId: groupId,
            page: 1,
            pageSize: recordPageSize,
            search: recordSearchRequest(for: query, groupId: groupId),
            context: context(for: groupId)
        )
        guard !Task.isCancelled, key == recordListKey(groupId: groupId, search: query) else { return }
        switch result {
        case .success(let page):
            applyRefreshedToken(page.refreshedToken)
            trackSource(page.source, forGroupId: groupId)
            recordSearchResultsByKey[key] = page.items
            recordSearchTotalsByKey[key] = page.pagination?.total ?? page.items.count
        case .failure(let failure):
            recordFailure(operation: "searchRecords", intent: .secondaryLoad, disposition: .silent, failure: failure)
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

    /// Navigation back to a member keeps every loaded page; mutations explicitly refresh.
    func loadMemberRecordsIfNeeded(groupId: String, memberId: String) async {
        let key = memberRecordKey(groupId: groupId, memberId: memberId)
        guard memberRecordsByKey[key] == nil else { return }
        await refreshMemberRecords(groupId: groupId, memberId: memberId)
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
        guard !loadingRecordKeys.contains(key) else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        let result = await ledgerRepository.memberRecords(
            groupId: groupId,
            memberId: memberId,
            page: 1,
            pageSize: recordPageSize,
            currencyCodes: recordFilters(for: groupId).currencyCodes.sorted(),
            context: context(for: groupId)
        )
        guard !Task.isCancelled, key == memberRecordKey(groupId: groupId, memberId: memberId) else { return }
        switch result {
        case .success(let snapshot):
            applyRefreshedToken(snapshot.refreshedToken)
            trackSource(snapshot.source, forGroupId: groupId)
            if let member = snapshot.member {
                replaceMemberProjection(groupId: groupId, member: member)
            }
            memberRecordsByKey[key] = snapshot.records
            memberRecordTotalsByKey[key] = snapshot.pagination?.total ?? snapshot.records.count
        case .failure(let failure):
            recordFailure(operation: "refreshMemberRecords", intent: .secondaryLoad, disposition: .silent, failure: failure)
        }
    }

    func loadMoreMemberRecords(groupId: String, memberId: String) async {
        if isFixtureMode { return }
        guard api.ledgerAPIEnabled else { return }
        let key = memberRecordKey(groupId: groupId, memberId: memberId)
        guard !loadingRecordKeys.contains(key) else { return }
        let current = memberRecordsByKey[key] ?? []
        let total = memberRecordTotalsByKey[key] ?? current.count
        guard current.count < total else { return }
        loadingRecordKeys.insert(key)
        defer { loadingRecordKeys.remove(key) }
        let page = current.count / recordPageSize + 1
        let result = await ledgerRepository.memberRecords(
            groupId: groupId,
            memberId: memberId,
            page: page,
            pageSize: recordPageSize,
            currencyCodes: recordFilters(for: groupId).currencyCodes.sorted(),
            context: context(for: groupId)
        )
        guard !Task.isCancelled, key == memberRecordKey(groupId: groupId, memberId: memberId) else { return }
        switch result {
        case .success(let snapshot):
            applyRefreshedToken(snapshot.refreshedToken)
            trackSource(snapshot.source, forGroupId: groupId)
            if let member = snapshot.member {
                replaceMemberProjection(groupId: groupId, member: member)
            }
            memberRecordsByKey[key] = current + snapshot.records
            memberRecordTotalsByKey[key] = snapshot.pagination?.total ?? total
        case .failure(let failure):
            recordFailure(operation: "loadMoreMemberRecords", intent: .pagination, disposition: .silent, failure: failure)
        }
    }

    func createGroup(name: String) async -> Bool {
        await createGroupWithFeedback(name: name, users: [], tempUsers: []).success
    }

    func createGroup(name: String, users: [UserProfile], tempUsers: [String]) async -> Bool {
        await createGroupWithFeedback(name: name, users: users, tempUsers: tempUsers).success
    }

    func createGroupWithFeedback(
        name: String,
        users: [UserProfile],
        tempUsers: [String],
        currencyCode: String? = nil
    ) async -> StoreActionResult {
        let normalizedCurrencyCode = CurrencyCatalog.normalizedCode(currencyCode)
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
                currencyCode: normalizedCurrencyCode,
                createdAt: Date().timeIntervalSince1970 * 1000,
                modifiedAt: Date().timeIntervalSince1970 * 1000,
                membersInfo: members,
                tempUsers: temps,
                archivedUsers: [],
                ownerUserId: user?.uuid,
                isOwner: true
            ), at: 0)
            recordsByGroup[groupId] = []
            recordTotals[groupId] = 0
            totalBalancesByCurrency = currencyBalancesFromLoadedGroups()
            return .success(createdGroupId: groupId)
        }
        return await withLoadingResult(operation: "createGroup") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            let context = createGroupLedgerContext()
            guard context.preferredSource != .local || users.isEmpty else {
                return .failure(L("Login to continue"))
            }
            let result = await ledgerRepository.createGroup(
                name: name,
                currencyCode: normalizedCurrencyCode,
                context: context
            )
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "createGroup", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            var createdGroupId: String?
            if let groupId = response.value, !groupId.isEmpty {
                createdGroupId = groupId
                trackSource(response.source, forGroupId: groupId)
                if !users.isEmpty {
                    let inviteResult = await ledgerRepository.invite(code: groupId, userIds: users.map(\.uuid), context: remoteLedgerContext())
                    guard case .success(let inviteResponse) = inviteResult else {
                        if case .failure(let failure) = inviteResult {
                            return actionFailure(operation: "createGroup.invite", failure: failure)
                        }
                        return .failure(nil)
                    }
                    applyRefreshedToken(inviteResponse.refreshedToken)
                }
                for tempUser in tempUsers where !tempUser.isEmpty {
                    let tempUserResult = await ledgerRepository.addTempUser(code: groupId, name: tempUser, context: context)
                    guard case .success(let tempUserResponse) = tempUserResult else {
                        if case .failure(let failure) = tempUserResult {
                            return actionFailure(operation: "createGroup.tempUser", failure: failure)
                        }
                        return .failure(nil)
                    }
                    applyRefreshedToken(tempUserResponse.refreshedToken)
                    trackSource(tempUserResponse.source, forGroupId: groupId)
                }
            }
            _ = await refreshHome(search: groupSearchQuery)
            if let createdGroupId {
                // A newly created group is empty before its first detail refresh.
                // Preserve any records that may already have been loaded meanwhile.
                if recordsByGroup[createdGroupId] == nil {
                    recordsByGroup[createdGroupId] = []
                    recordTotals[createdGroupId] = 0
                }
                return .success(createdGroupId: createdGroupId)
            }
            return .success
        }
    }

    func joinGroup(code: String) async -> Bool {
        await joinGroupWithFeedback(code: code).success
    }

    func joinGroupWithFeedback(code: String) async -> JoinGroupResult {
        guard api.ledgerAPIEnabled else {
            return JoinGroupResult(success: false, message: nil)
        }
        let result = await ledgerRepository.joinGroup(code: code, context: remoteLedgerContext())
        switch result {
        case .success(let response):
            applyRefreshedToken(response.refreshedToken)
            await refreshHome()
            return JoinGroupResult(success: true, message: response.message)
        case .failure(let failure):
            recordFailure(operation: "joinGroup", intent: .userAction, disposition: .local, failure: failure)
            return JoinGroupResult(success: false, message: failure.message ?? L("Network issues"))
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
            let context = context(for: code)
            let result = await ledgerRepository.archiveGroup(code: code, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "archiveGroup", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: code)
            _ = await refreshHome(search: groupSearchQuery)
            return .success
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
            let context = context(for: code)
            let result = await ledgerRepository.unarchiveGroup(code: code, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "unarchiveGroup", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: code)
            _ = await refreshHome(search: groupSearchQuery)
            return .success
        }
    }

    func deleteGroup(_ code: String) async -> Bool {
        await deleteGroupWithFeedback(code).success
    }

    func deleteGroupWithFeedback(_ code: String) async -> StoreActionResult {
        if let group = group(id: code), !group.canCurrentUserDelete {
            return .failure(nil)
        }
        if isFixtureMode {
            groups.removeAll { $0.id == code }
            recordsByGroup[code] = nil
            recordTotals[code] = nil
            return .success
        }
        return await withLoadingResult(operation: "deleteGroup") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            let context = context(for: code)
            let result = await ledgerRepository.deleteGroup(code: code, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "deleteGroup", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            groupSourceById[code] = nil
            clearRecordCaches(for: code)
            recordsByGroup[code] = nil
            recordTotals[code] = nil
            _ = await refreshHome(search: groupSearchQuery)
            return .success
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
            let context = context(for: code)
            let result = await ledgerRepository.changeGroupName(code: code, name: name, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "changeGroupName", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: code)
            await refreshGroup(code)
            return .success
        }
    }

    func changeGroupCurrencyWithFeedback(_ code: String, currencyCode: String) async -> StoreActionResult {
        let normalized = CurrencyCatalog.normalizedCode(currencyCode)
        if isFixtureMode {
            guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(nil) }
            groups[index].currencyCode = normalized
            groups[index].modifiedAt = Date().timeIntervalSince1970 * 1000
            totalBalancesByCurrency = currencyBalancesFromLoadedGroups()
            return .success
        }
        return await withLoadingResult(operation: "changeGroupCurrency") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            let context = context(for: code)
            let result = await ledgerRepository.changeGroupCurrency(code: code, currencyCode: normalized, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "changeGroupCurrency", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: code)
            await refreshGroup(code)
            _ = await refreshHome(search: groupSearchQuery)
            return .success
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
            let context = context(for: groupId)
            guard context.preferredSource != .local || users.isEmpty else {
                return .failure(L("Login to continue"))
            }
            if !users.isEmpty {
                let result = await ledgerRepository.invite(code: groupId, userIds: users.map(\.uuid), context: remoteLedgerContext())
                guard case .success(let response) = result else {
                    if case .failure(let failure) = result {
                        return actionFailure(operation: "addMembers.invite", failure: failure)
                    }
                    return .failure(nil)
                }
                applyRefreshedToken(response.refreshedToken)
            }
            for tempUser in tempUsers where !tempUser.isEmpty {
                let result = await ledgerRepository.addTempUser(code: groupId, name: tempUser, context: context)
                guard case .success(let response) = result else {
                    if case .failure(let failure) = result {
                        return actionFailure(operation: "addMembers.tempUser", failure: failure)
                    }
                    return .failure(nil)
                }
                applyRefreshedToken(response.refreshedToken)
                trackSource(response.source, forGroupId: groupId)
            }
            await refreshGroup(groupId)
            return .success
        }
    }

    func canRemoveMember(_ member: Member, from group: WalkGroup) -> Bool {
        group.isOwner && member.uuid != group.ownerUserId && !member.hasUnresolvedCurrencyBalance
    }

    func removeMemberWithFeedback(groupId: String, member: Member) async -> StoreActionResult {
        guard let group = group(id: groupId), canRemoveMember(member, from: group) else {
            return .failure(L("Settle this member's balance before removing them."))
        }
        if isFixtureMode {
            guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return .failure(nil) }
            groups[index].membersInfo.removeAll { $0.uuid == member.uuid }
            groups[index].tempUsers.removeAll { $0.uuid == member.uuid }
            groups[index].participantCount = groups[index].allMembers.count
            groups[index].participantPreview = Array(groups[index].allMembers.prefix(4))
            return .success
        }
        return await withLoadingResult(operation: "removeMember") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            let result = await ledgerRepository.removeMember(code: groupId, participantId: member.uuid, context: context(for: groupId))
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "removeMember", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: groupId)
            await refreshGroupAfterLedgerMutation(groupId)
            return .success
        }
    }

    func canMutateRecord(_ record: WalkRecord, in group: WalkGroup) -> Bool {
        let memberIds = Set(group.allMembers.map(\.uuid))
        return memberIds.contains(record.who) && record.forWhom.allSatisfy(memberIds.contains)
    }

    func searchUsers(name: String) async -> [UserProfile] {
        if isFixtureMode {
            let names = ["Alexandra", "Christopher", "Noah", "Ivy", "Owen", "Tara", "June", "Keith", "Lin", "Ming", "Yan"]
            return names
                .filter { $0.localizedCaseInsensitiveContains(name) }
                .map { UserProfile(uuid: "fixture-\($0)", name: $0, avatar: "") }
        }
        guard api.ledgerAPIEnabled else { return [] }
        guard !name.isEmpty else { return [] }
        let result = await ledgerRepository.searchUsers(name: name, context: remoteLedgerContext())
        switch result {
        case .success(let response):
            applyRefreshedToken(response.refreshedToken)
            return response.value ?? []
        case .failure(let failure):
            recordFailure(operation: "searchUsers", intent: .secondaryLoad, disposition: .silent, failure: failure)
            return []
        }
    }

    func addRecord(groupId: String, who: String, paid: String, forWhom: [String], type: String, text: String, long: String = "", lat: String = "", occurredAt: TimeInterval, currencyCode: String? = nil) async -> Bool {
        await addRecordWithFeedback(groupId: groupId, who: who, paid: paid, forWhom: forWhom, type: type, text: text, long: long, lat: lat, occurredAt: occurredAt, currencyCode: currencyCode).success
    }

    func addRecordWithFeedback(groupId: String, who: String, paid: String, forWhom: [String], type: String, text: String, long: String = "", lat: String = "", occurredAt: TimeInterval, currencyCode: String? = nil) async -> StoreActionResult {
        let resolvedCurrencyCode = CurrencyCatalog.normalizedCode(currencyCode ?? group(id: groupId)?.currencyCode)
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
                isDebtResolve: false,
                currencyCode: resolvedCurrencyCode
            )
            recordsByGroup[groupId, default: []].insert(record, at: 0)
            recordTotals[groupId] = recordsByGroup[groupId]?.count ?? 0
            clearRecordCaches(for: groupId)
            return .success
        }
        return await withLoadingResult(operation: "addRecord") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let paidMinor = try? Money.parseDisplay(paid), Money.isPositive(paidMinor) else { return .failure(L("Enter a valid amount with up to 2 decimal places")) }
            let context = context(for: groupId)
            let result = await ledgerRepository.addRecord(groupId: groupId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, long: long, lat: lat, occurredAt: occurredAt, currencyCode: resolvedCurrencyCode, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "addRecord", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: groupId)
            await refreshGroupAfterLedgerMutation(groupId)
            return .success
        }
    }

    func editRecord(groupId: String, recordId: String, who: String, paid: String, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool = false, currencyCode: String? = nil) async -> Bool {
        await editRecordWithFeedback(groupId: groupId, recordId: recordId, who: who, paid: paid, forWhom: forWhom, type: type, text: text, occurredAt: occurredAt, isSettlement: isSettlement, currencyCode: currencyCode).success
    }

    func editRecordWithFeedback(groupId: String, recordId: String, who: String, paid: String, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool = false, currencyCode: String? = nil) async -> StoreActionResult {
        if let group = group(id: groupId),
           let record = recordsByGroup[groupId]?.first(where: { $0.recordId == recordId }),
           !canMutateRecord(record, in: group) {
            return .failure(nil)
        }
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
            recordsByGroup[groupId]?[index].currencyCode = CurrencyCatalog.normalizedCode(currencyCode ?? recordsByGroup[groupId]?[index].currencyCode ?? group(id: groupId)?.currencyCode)
            recordsByGroup[groupId]?[index].modifiedAt = Date().timeIntervalSince1970 * 1000
            clearRecordCaches(for: groupId)
            return .success
        }
        return await withLoadingResult(operation: "editRecord") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            guard let paidMinor = try? Money.parseDisplay(paid), Money.isPositive(paidMinor) else { return .failure(L("Enter a valid amount with up to 2 decimal places")) }
            let context = context(for: groupId)
            let result = await ledgerRepository.updateRecord(groupId: groupId, recordId: recordId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, occurredAt: occurredAt, isSettlement: isSettlement, currencyCode: currencyCode, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "editRecord", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: groupId)
            await refreshGroupAfterLedgerMutation(groupId)
            return .success
        }
    }

    func deleteRecord(groupId: String, recordId: String) async -> Bool {
        await deleteRecordWithFeedback(groupId: groupId, recordId: recordId).success
    }

    func deleteRecordWithFeedback(groupId: String, recordId: String) async -> StoreActionResult {
        if let group = group(id: groupId),
           let record = recordsByGroup[groupId]?.first(where: { $0.recordId == recordId }),
           !canMutateRecord(record, in: group) {
            return .failure(nil)
        }
        if isFixtureMode {
            recordsByGroup[groupId]?.removeAll { $0.recordId == recordId }
            recordTotals[groupId] = recordsByGroup[groupId]?.count ?? 0
            clearRecordCaches(for: groupId)
            return .success
        }
        return await withLoadingResult(operation: "deleteRecord") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            let context = context(for: groupId)
            let result = await ledgerRepository.deleteRecord(groupId: groupId, recordId: recordId, context: context)
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "deleteRecord", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: groupId)
            await refreshGroupAfterLedgerMutation(groupId)
            return .success
        }
    }

    func resolveSingle(groupId: String, debt: ResolvedDebt) async -> Bool {
        await resolveSingleWithFeedback(groupId: groupId, debt: debt).success
    }

    func resolveSingleWithFeedback(groupId: String, debt: ResolvedDebt) async -> StoreActionResult {
        await withLoadingResult(operation: "resolveSingle") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            let context = context(for: groupId)
            let result = await ledgerRepository.addSettlementRecord(
                groupId: groupId,
                fromId: debt.from.uuid,
                toId: debt.to.uuid,
                amountMinor: debt.amountMinor,
                note: "resolve",
                currencyCode: debt.currencyCode,
                context: context
            )
            guard case .success(let response) = result else {
                if case .failure(let failure) = result {
                    return actionFailure(operation: "resolveSingle", failure: failure)
                }
                return .failure(nil)
            }
            applyRefreshedToken(response.refreshedToken)
            trackSource(response.source, forGroupId: groupId)
            await refreshGroupAfterLedgerMutation(groupId)
            return .success
        }
    }

    func resolveAll(groupId: String, debts: [ResolvedDebt]) async -> Bool {
        await resolveAllWithFeedback(groupId: groupId, debts: debts).success
    }

    func resolveAllWithFeedback(groupId: String, debts: [ResolvedDebt]) async -> StoreActionResult {
        await withLoadingResult(operation: "resolveAll") {
            guard api.ledgerAPIEnabled else { return .failure(nil) }
            let context = context(for: groupId)
            let currencyCodes = Set(debts.map { CurrencyCatalog.normalizedCode($0.currencyCode) })
            let resolvedCodes = currencyCodes.isEmpty
                ? [CurrencyCatalog.normalizedCode(group(id: groupId)?.currencyCode)]
                : currencyCodes.sorted()
            for currencyCode in resolvedCodes {
                let result = await ledgerRepository.resolveDebts(
                    groupId: groupId,
                    currencyCode: currencyCode,
                    context: context
                )
                guard case .success(let response) = result else {
                    await refreshGroupAfterLedgerMutation(groupId)
                    if case .failure(let failure) = result {
                        return actionFailure(operation: "resolveAll", failure: failure)
                    }
                    return .failure(nil)
                }
                applyRefreshedToken(response.refreshedToken)
                trackSource(response.source, forGroupId: groupId)
            }
            await refreshGroupAfterLedgerMutation(groupId)
            return .success
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
        guard let cached = settlementSuggestionsByGroup[group.id] else {
            return []
        }
        let debts: [ResolvedDebt] = cached.compactMap { transfer in
            guard let from = group.allMembers.first(where: { $0.uuid == transfer.fromId }),
                  let to = group.allMembers.first(where: { $0.uuid == transfer.toId }) else {
                return nil
            }
            return ResolvedDebt(
                from: from,
                to: to,
                amountMinor: transfer.amountMinor,
                currencyCode: CurrencyCatalog.normalizedCode(transfer.currencyCode ?? group.currencyCode)
            )
        }
        return BalancePresentation.sortedByAbsoluteAmount(debts)
    }

    func currentParticipantID(for group: WalkGroup) -> String? {
        if isLocalLedgerGroup(group.id) {
            return localOwner.uuid
        }
        return user?.uuid
    }

    func personalResolvedDebts(for group: WalkGroup) -> [ResolvedDebt] {
        BalancePresentation.personalDebts(
            visibleResolvedDebts(for: group),
            participantID: currentParticipantID(for: group)
        )
    }

    func isSettlementSuggestionReady(for groupId: String) -> Bool {
        isFixtureMode
            || settlementSuggestionsByGroup[groupId] != nil
            || settlementSuggestionReadyGroupIds.contains(groupId)
    }

    func balancesInServerOrder(for group: WalkGroup) -> [Member] {
        group.allMembers
    }

    func refreshSettlementSuggestion(groupId: String) async {
        if isFixtureMode { return }
        guard let group = group(id: groupId) else { return }
        defer { settlementSuggestionReadyGroupIds.insert(groupId) }
        let context = context(for: groupId)
        var merged: [SettlementTransfer] = []
        var receivedResponse = false
        for currencyCode in settlementCurrencyCodes(for: group) {
            let result = await ledgerRepository.settlementSuggestion(
                groupId: groupId,
                currencyCode: currencyCode,
                context: context
            )
            switch result {
            case .success(let response):
                receivedResponse = true
                applyRefreshedToken(response.refreshedToken)
                trackSource(response.source, forGroupId: groupId)
                merged.append(contentsOf: (response.value ?? []).map { transfer in
                    var next = transfer
                    next.currencyCode = CurrencyCatalog.normalizedCode(transfer.currencyCode ?? currencyCode)
                    return next
                })
            case .failure(let failure):
                recordFailure(operation: "refreshSettlementSuggestion", intent: .secondaryLoad, disposition: .silent, failure: failure)
            }
        }
        if receivedResponse {
            settlementSuggestionsByGroup[groupId] = merged.sorted(by: settlementTransferSort)
        }
    }

    private func settlementCurrencyCodes(for group: WalkGroup) -> [String] {
        var codes = Set<String>()
        for balance in group.currentUserCurrencyBalances where balance.hasLedgerActivity {
            codes.insert(CurrencyCatalog.normalizedCode(balance.currencyCode))
        }
        for member in group.allMembers {
            for balance in member.currencyBalances where balance.hasLedgerActivity {
                codes.insert(CurrencyCatalog.normalizedCode(balance.currencyCode))
            }
        }
        for record in recordsByGroup[group.id] ?? [] {
            codes.insert(CurrencyCatalog.normalizedCode(record.currencyCode ?? group.currencyCode))
        }
        if codes.isEmpty, group.hasUnresolvedBalance {
            codes.insert(CurrencyCatalog.normalizedCode(group.currencyCode))
        }
        return codes.sorted()
    }

    private func settlementTransferSort(_ left: SettlementTransfer, _ right: SettlementTransfer) -> Bool {
        let amountOrder = Money.compare(Money.absolute(left.amountMinor), Money.absolute(right.amountMinor))
        if amountOrder != .orderedSame {
            return amountOrder == .orderedDescending
        }
        let leftCurrency = CurrencyCatalog.normalizedCode(left.currencyCode)
        let rightCurrency = CurrencyCatalog.normalizedCode(right.currencyCode)
        if leftCurrency != rightCurrency {
            return leftCurrency < rightCurrency
        }
        if left.fromId != right.fromId {
            return left.fromId < right.fromId
        }
        return left.toId < right.toId
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
        if pendingGroupPins[incoming.id] != nil {
            merged.pinnedAt = existing.pinnedAt
        }
        if incoming.allMembers.isEmpty, !existing.allMembers.isEmpty {
            merged.membersInfo = existing.membersInfo
            merged.tempUsers = existing.tempUsers
        }
        if merged.participantPreview.isEmpty {
            merged.participantPreview = existing.participantPreview
        }
        if merged.historicalMembers.isEmpty {
            merged.historicalMembers = existing.historicalMembers
        }
        if merged.participantCount == 0 {
            merged.participantCount = max(existing.participantCount, merged.allMembers.count, merged.participantPreview.count)
        }
        return merged
    }

    private func mergingLocalGroupRows(_ rows: [WalkGroup]) -> [WalkGroup] {
        let local = rows.filter { isLocalLedgerGroup($0.id) }
        let remote = rows.filter { !isLocalLedgerGroup($0.id) }
        return WalkGroup.mergingLocalGroups(local, into: remote)
    }

    private func appendGroups(_ nextGroups: [WalkGroup]) {
        for group in nextGroups {
            replaceGroup(group)
        }
        groups = mergingLocalGroupRows(groups)
    }

    private func resolvedCurrencyBalances(from snapshot: LedgerHomeSnapshot) -> [CurrencyBalanceSummary] {
        if !snapshot.currencyBalances.isEmpty {
            return snapshot.currencyBalances.sorted { $0.currencyCode < $1.currencyCode }
        }
        guard let totalBalanceMinor = snapshot.totalBalanceMinor,
              !Money.isZero(totalBalanceMinor) else { return [] }
        return [CurrencyBalanceSummary(
            currencyCode: CurrencyCatalog.defaultCurrencyCode(),
            totalBalanceMinor: totalBalanceMinor
        )]
    }

    private func mergedCurrencyBalances(
        _ first: [CurrencyBalanceSummary],
        _ second: [CurrencyBalanceSummary]
    ) -> [CurrencyBalanceSummary] {
        let totals = (first + second).reduce(into: [String: MoneyMinor]()) { result, balance in
            let currencyCode = CurrencyCatalog.normalizedCode(balance.currencyCode)
            result[currencyCode] = Money.add(
                result[currencyCode] ?? "0",
                balance.totalBalanceMinor
            )
        }
        return totals.keys.sorted().map { currencyCode in
            CurrencyBalanceSummary(
                currencyCode: currencyCode,
                totalBalanceMinor: totals[currencyCode] ?? "0"
            )
        }
    }

    private func currencyBalancesFromLoadedGroups() -> [CurrencyBalanceSummary] {
        let identityIds = Set([localOwner.uuid, user?.uuid].compactMap { $0 })
        let totals = groups.reduce(into: [String: MoneyMinor]()) { result, group in
            guard identityIds.isDisjoint(with: Set(group.archivedUsers)) else { return }
            let member = group.allMembers.first { identityIds.contains($0.uuid) }
            let currencyBalances = group.hasCurrentUserBalanceSummary
                ? group.currentUserCurrencyBalances
                : member?.currencyBalances ?? []
            let actualBalances = currencyBalances.filter(\.hasLedgerActivity)
            if actualBalances.isEmpty {
                let currencyCode = CurrencyCatalog.normalizedCode(group.currencyCode)
                let balance = group.hasCurrentUserBalanceSummary
                    ? group.currentUserBalanceMinor
                    : member?.debtMinor ?? "0"
                guard !Money.isZero(balance) else { return }
                result[currencyCode] = Money.add(result[currencyCode] ?? "0", balance)
            } else {
                for balance in actualBalances {
                    let currencyCode = CurrencyCatalog.normalizedCode(balance.currencyCode)
                    result[currencyCode] = Money.add(result[currencyCode] ?? "0", balance.debtMinor)
                }
            }
        }
        return totals.keys.sorted().map { currencyCode in
            CurrencyBalanceSummary(
                currencyCode: currencyCode,
                totalBalanceMinor: totals[currencyCode] ?? "0"
            )
        }
    }

    private func clearRecordCaches(for groupId: String) {
        recordCacheRevisions[groupId, default: 0] += 1
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
        "\(groupId)::records::\(recordCacheRevisions[groupId, default: 0])::\(recordFilters(for: groupId).currencyCodes.sorted().joined(separator: ","))::\(recordFilters(for: groupId).onlyRelatedToMe)::\(recordFilters(for: groupId).categoryIds.sorted().joined(separator: ","))::\(search)"
    }

    private func memberRecordKey(groupId: String, memberId: String) -> String {
        "\(groupId)::member::\(recordCacheRevisions[groupId, default: 0])::\(memberId)::\(recordFilters(for: groupId).currencyCodes.sorted().joined(separator: ","))"
    }

    private func normalizedQuery(_ query: String?) -> String {
        query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func optionalQuery(_ query: String) -> String? {
        query.isEmpty ? nil : query
    }

    private func recordSearchRequest(for query: String, groupId: String) -> RecordSearchRequest? {
        let filters = recordFilters(for: groupId)
        guard !query.isEmpty || filters.isActive else { return nil }
        var request = query.isEmpty ? RecordSearchRequest(operator: "or", conditions: []) : .noteOrCategoryName(query: query)
        request.currencyCodes = filters.currencyCodes.sorted()
        request.categoryIds = filters.categoryIds.sorted()
        request.includeSettlements = filters.categoryIds.contains(transferCategory.id)
        if filters.onlyRelatedToMe {
            request.participantId = group(id: groupId).flatMap { currentParticipantID(for: $0) }
        }
        return request
    }

    private func localSearchMatches(groupId: String, query: String) -> [WalkRecord] {
        (recordsByGroup[groupId] ?? []).filter {
            recordSearchRequest(for: query, groupId: groupId)?.matches($0, defaultCurrency: group(id: groupId)?.currencyCode) ?? true
        }
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

    private func applyRefreshedToken(_ refreshedToken: String?) {
        guard let refreshedToken else {
            return
        }
        token = refreshedToken
        UserDefaults.standard.set(refreshedToken, forKey: "walkcalc.token")
    }

    private static func loadLocalOwnerId() -> String {
        let key = "walkcalc.localOwnerId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = "local-user-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    private func recordCurrencyPreferenceKey(_ groupId: String) -> String {
        "walkcalc.recordCurrency.\(groupId)"
    }

    var localOwner: Member {
        let displayName = user?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Member(
            uuid: localOwnerId,
            name: displayName?.isEmpty == false ? displayName ?? L("Me") : L("Me"),
            avatar: user?.avatar ?? "",
            debtMinor: "0",
            costMinor: "0"
        )
    }

    func localLedgerContext() -> LedgerSessionContext {
        LedgerSessionContext.local(owner: localOwner)
    }

    func context(for groupId: String) -> LedgerSessionContext {
        if sourceMetadata(for: groupId)?.source == .local || Self.isLocalIdentifier(groupId) {
            return localLedgerContext()
        }
        return remoteLedgerContext()
    }

    func sourceMetadata(for groupId: String) -> LedgerSourceMetadata? {
        groupSourceById[groupId]
    }

    func isLocalLedgerGroup(_ groupId: String) -> Bool {
        sourceMetadata(for: groupId)?.source == .local || Self.isLocalIdentifier(groupId)
    }

    private func homeLedgerContext() -> LedgerSessionContext? {
        if preferredLedgerSource == .local {
            return localLedgerContext()
        }
        guard let token else { return nil }
        return remoteLedgerContext(token: token)
    }

    private static func isLocalIdentifier(_ id: String) -> Bool {
        id.hasPrefix("local-") || id.hasPrefix("l-")
    }

    private func createGroupLedgerContext() -> LedgerSessionContext {
        if preferredLedgerSource == .local || token == nil {
            return localLedgerContext()
        }
        return remoteLedgerContext()
    }

    private func remoteLedgerContext(token: String? = nil) -> LedgerSessionContext {
        LedgerSessionContext.remote(accessToken: token ?? self.token)
    }

    private func trackSource(_ source: LedgerSourceMetadata, for groups: [WalkGroup]) {
        for group in groups {
            trackSource(source, for: group)
        }
    }

    private func trackSource(_ source: LedgerSourceMetadata, for group: WalkGroup) {
        trackSource(source, forGroupId: group.id)
    }

    private func trackSource(_ source: LedgerSourceMetadata, forGroupId groupId: String) {
        guard !groupId.isEmpty else { return }
        var metadata = source
        switch source.source {
        case .local:
            if metadata.localIdentifier == nil {
                metadata.localIdentifier = groupId
            }
        case .remote:
            if metadata.remoteIdentifier == nil {
                metadata.remoteIdentifier = groupId
            }
        }
        groupSourceById[groupId] = metadata
    }

    private func handleUnrecoverableAuthFailure(operation: String) {
        networkFeedbackLogger.notice("Auth failure operation=\(operation, privacy: .public)")
        token = nil
        user = nil
        resetLedgerState()
        isSigningIn = false
        preferredLedgerSource = .local
        startupRoute = .authenticated
        NativeAuthSession.clearAuthCookies(baseURL: api.baseURL, webBaseURL: api.webBaseURL)
        UserDefaults.standard.removeObject(forKey: "walkcalc.token")
        UserDefaults.standard.removeObject(forKey: "walkcalc.cachedUser")
        Task { @MainActor in
            _ = await refreshHome()
        }
    }

    private func isUnrecoverableAuthFailure<T>(_ response: APIEnvelope<T>) -> Bool {
        response.statusCode == 401 || response.statusCode == 403
    }

    private func isUnrecoverableAuthFailure(_ error: Error) -> Bool {
        guard let clientError = error as? APIClientError else { return false }
        return clientError.statusCode == 401 || clientError.statusCode == 403
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

    private func actionFailure(operation: String, failure: LedgerOperationFailure) -> StoreActionResult {
        recordFailure(operation: operation, intent: .userAction, disposition: .local, failure: failure)
        return .failure(failure.messageWithLimitDetail)
    }

    @discardableResult
    private func recordFailure<T>(operation: String, intent: NetworkOperationIntent, disposition: FeedbackDisposition, response: APIEnvelope<T>) -> Bool {
        if isUnrecoverableAuthFailure(response) {
            handleUnrecoverableAuthFailure(operation: operation)
            return true
        }
        let kind = response.failureKind?.rawValue ?? APIFailureKind.serverEnvelope.rawValue
        let status = response.statusCode ?? 0
        networkFeedbackLogger.info("Network failure operation=\(operation, privacy: .public) intent=\(intent.rawValue, privacy: .public) disposition=\(disposition.rawValue, privacy: .public) kind=\(kind, privacy: .public) status=\(status, privacy: .public)")
        return false
    }

    @discardableResult
    private func recordFailure(operation: String, intent: NetworkOperationIntent, disposition: FeedbackDisposition, failure: LedgerOperationFailure) -> Bool {
        if failure.kind == .unrecoverableAuth {
            handleUnrecoverableAuthFailure(operation: operation)
            return true
        }
        let status = failure.statusCode ?? 0
        networkFeedbackLogger.info("Ledger failure operation=\(operation, privacy: .public) intent=\(intent.rawValue, privacy: .public) disposition=\(disposition.rawValue, privacy: .public) kind=\(String(describing: failure.kind), privacy: .public) status=\(status, privacy: .public)")
        return false
    }

    @discardableResult
    private func recordFailure(operation: String, intent: NetworkOperationIntent, disposition: FeedbackDisposition, error: Error) -> Bool {
        if isUnrecoverableAuthFailure(error) {
            handleUnrecoverableAuthFailure(operation: operation)
            return true
        }
        let clientError = error as? APIClientError
        let kind = clientError?.kind.rawValue ?? APIFailureKind.transport.rawValue
        let status = clientError?.statusCode ?? 0
        networkFeedbackLogger.info("Network failure operation=\(operation, privacy: .public) intent=\(intent.rawValue, privacy: .public) disposition=\(disposition.rawValue, privacy: .public) kind=\(kind, privacy: .public) status=\(status, privacy: .public)")
        return false
    }
}

private extension LedgerOperationFailure {
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
