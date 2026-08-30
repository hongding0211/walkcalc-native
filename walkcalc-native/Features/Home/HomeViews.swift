import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

enum Route: Hashable {
    case group(String)
}

enum HomeSheet: Identifiable {
    case create
    case join
    case settings
    case archivedGroups
    case about
    case signIn

    var id: String {
        switch self {
        case .create: "create"
        case .join: "join"
        case .settings: "settings"
        case .archivedGroups: "archivedGroups"
        case .about: "about"
        case .signIn: "signIn"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.startupRoute {
            case .resolving:
                LaunchGateView()
            case .authenticated:
                RootHomeView()
            case .loginRequired:
                RootHomeView()
            }
        }
        .task {
            await store.prepareNetworkAccessForStartup()
            await store.bootstrap()
            if !store.shouldSkipNotificationPermissionRequest {
                await store.requestNotificationPermissionIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await store.handleForegroundActivation()
            }
        }
        .alert(item: Binding(get: { store.urgentAlert }, set: { store.urgentAlert = $0 })) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L("Confirm"))) {
                    store.urgentAlert = nil
                }
            )
        }
    }
}

private struct LaunchGateView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let layout = LoginLayout(size: proxy.size)
            let markScale = layout.scale * 1.08

            ZStack(alignment: .topLeading) {
                background
                    .ignoresSafeArea()

                LoginBrandMark(scale: markScale)
                    .frame(width: layout.value(70.2), height: layout.value(80.229))
                    .offset(x: layout.x(8), y: layout.y(308))

                Text("Walking Calculator")
                    .font(.custom("PingFangSC-Semibold", size: layout.value(21)))
                    .foregroundStyle(primaryText)
                    .frame(width: layout.value(310), alignment: .leading)
                    .lineLimit(1)
                    .offset(x: layout.x(42), y: layout.y(412))
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel(Text("Walking Calculator"))
    }

    private var background: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0x050505)) : Color(UIColor(hex: 0xF4F4F5))
    }

    private var primaryText: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0xF5F5F2)) : Color(UIColor(hex: 0x1E1E1E))
    }
}

struct LoginView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @State private var showingSSO = false
    @State private var isAppleAuthorizationInFlight = false
    @State private var currentAppleNonce: String?

    var body: some View {
        LoginScreen(
            isSigningIn: store.isSigningIn,
            isAppleAuthorizationInFlight: isAppleAuthorizationInFlight,
            onLogin: {
                showingSSO = true
            },
            onAppleRequest: { request in
                let nonce = randomNonceString()
                currentAppleNonce = nonce
                isAppleAuthorizationInFlight = true
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(nonce)
            },
            onAppleCompletion: { result in
                handleAppleCompletion(result)
            }
        )
        .sheet(isPresented: $showingSSO) {
            SSOLoginView { token in
                showingSSO = false
                Task {
                    await store.signIn(token: token)
                }
            }
            .immersiveWebSheet()
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                currentAppleNonce = nil
                isAppleAuthorizationInFlight = false
                return
            }
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let fullName = credential.fullName.flatMap { components -> String? in
                let value = PersonNameComponentsFormatter().string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let nonce = currentAppleNonce
            currentAppleNonce = nil
            isAppleAuthorizationInFlight = false
            Task {
                await store.signInWithApple(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    fullName: fullName,
                    nonce: nonce
                )
            }
        case .failure(let error):
            currentAppleNonce = nil
            isAppleAuthorizationInFlight = false
            if (error as? ASAuthorizationError)?.code == .canceled {
                return
            }
        }
    }
}

struct SignInSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss

    let onDone: () -> Void

    var body: some View {
        LoginView()
            .onChange(of: store.isLoggedIn) { _, isLoggedIn in
                guard isLoggedIn else { return }
                dismiss()
                onDone()
            }
    }
}

private struct LoginScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let isSigningIn: Bool
    let isAppleAuthorizationInFlight: Bool
    let onLogin: () -> Void
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = LoginLayout(size: proxy.size)
            let markScale = layout.scale * 1.08
            let buttonWidth = layout.value(318)
            let buttonHeight = layout.value(40)
            let buttonCornerRadius = buttonHeight / 2
            let buttonX = layout.x(36)
            let buttonGroupY = layout.y(664)

            ZStack(alignment: .topLeading) {
                loginBackground
                    .ignoresSafeArea()

                LoginBrandMark(scale: markScale)
                    .frame(width: layout.value(70.2), height: layout.value(80.229))
                    .offset(x: layout.x(8), y: layout.y(308))

                Text("Walking Calculator")
                    .font(.system(size: layout.value(21), weight: .semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: layout.value(310), alignment: .leading)
                    .lineLimit(1)
                    .offset(x: layout.x(42), y: layout.y(412))

                Text(L("Sign in to continue"))
                    .font(.custom("PingFangSC-Medium", size: layout.value(15)))
                    .foregroundStyle(secondaryText)
                    .frame(width: layout.value(260), alignment: .leading)
                    .lineLimit(1)
                    .offset(x: layout.x(42), y: layout.y(446))

                VStack(spacing: layout.value(12)) {
                    NativeSignInWithAppleButton(
                        style: colorScheme == .dark ? .white : .black,
                        cornerRadius: buttonCornerRadius,
                        onRequest: onAppleRequest,
                        onCompletion: onAppleCompletion
                    )
                    .frame(width: buttonWidth, height: buttonHeight)
                    .id(colorScheme == .dark ? "apple-sign-in-dark" : "apple-sign-in-light")
                    .disabled(isInteractionDisabled)

                    Button(action: onLogin) {
                        HStack(spacing: layout.value(8)) {
                            if isSigningIn {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(secondaryButtonForeground)
                            }
                            Text(L("Sign in"))
                        }
                        .font(.system(size: layout.value(14.5), weight: .semibold))
                        .foregroundStyle(secondaryButtonForeground)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .background(secondaryButtonBackground, in: RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isInteractionDisabled)
                }
                .frame(width: buttonWidth)
                .offset(x: buttonX, y: buttonGroupY)
            }
        }
        .ignoresSafeArea()
    }

    private var loginBackground: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0x050505)) : Color(UIColor(hex: 0xF4F4F5))
    }

    private var primaryText: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0xF5F5F2)) : Color(UIColor(hex: 0x1E1E1E))
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0x8F8F8A)) : Color(UIColor(hex: 0xA9A9A9))
    }

    private var secondaryButtonBackground: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0x303338)) : Color(UIColor(hex: 0xE4E5E7))
    }

    private var secondaryButtonForeground: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0xF5F5F2)) : Color(UIColor(hex: 0x1E1E1E))
    }

    private var isInteractionDisabled: Bool {
        isSigningIn || isAppleAuthorizationInFlight
    }
}

private struct NativeSignInWithAppleButton: UIViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let cornerRadius: CGFloat
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: style)
        button.cornerRadius = cornerRadius
        button.addTarget(context.coordinator, action: #selector(Coordinator.performRequest), for: .touchUpInside)
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        button.cornerRadius = cornerRadius
        context.coordinator.onRequest = onRequest
        context.coordinator.onCompletion = onCompletion
        context.coordinator.button = button
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRequest: onRequest, onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var onRequest: (ASAuthorizationAppleIDRequest) -> Void
        var onCompletion: (Result<ASAuthorization, Error>) -> Void
        weak var button: ASAuthorizationAppleIDButton?

        init(
            onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
            onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void
        ) {
            self.onRequest = onRequest
            self.onCompletion = onCompletion
        }

        @objc func performRequest() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            onRequest(request)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            onCompletion(.success(authorization))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            onCompletion(.failure(error))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            guard let window = button?.window else {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                    return keyWindow
                }
                if let scene = scenes.first {
                    return UIWindow(windowScene: scene)
                }
                fatalError("Missing window scene for Sign in with Apple presentation.")
            }
            return window
        }
    }
}

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        var randoms = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
        if status != errSecSuccess {
            fatalError("Unable to generate nonce.")
        }

        randoms.forEach { random in
            if remainingLength == 0 {
                return
            }
            if Int(random) < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }

    return result
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.map { String(format: "%02x", $0) }.joined()
}

private struct LoginLayout {
    private static let baseSize = CGSize(width: 390, height: 844)

    let scale: CGFloat
    private let origin: CGPoint

    init(size: CGSize) {
        let rawScale = min(size.width / Self.baseSize.width, size.height / Self.baseSize.height)
        scale = min(max(rawScale, 0.82), 1.0)
        let layoutSize = CGSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
        origin = CGPoint(x: (size.width - layoutSize.width) / 2, y: (size.height - layoutSize.height) / 2)
    }

    func value(_ base: CGFloat) -> CGFloat {
        base * scale
    }

    func x(_ base: CGFloat) -> CGFloat {
        origin.x + value(base)
    }

    func y(_ base: CGFloat) -> CGFloat {
        origin.y + value(base)
    }
}

private struct LoginBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    let scale: CGFloat

    private var leftCapsule: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0xF8F8F5)) : Color(UIColor(hex: 0xB6B6B6))
    }

    private var rightCapsule: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0xA0A09C)) : Color(UIColor(hex: 0x050505))
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.38 : 0.18
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 13.638 * scale, style: .continuous)
                .fill(leftCapsule)
                .frame(width: 27.277 * scale, height: 49.911 * scale)
                .shadow(color: .black.opacity(shadowOpacity), radius: 4.643 * scale, y: 1.741 * scale)
                .offset(x: 12.77 * scale, y: 12.19 * scale)

            RoundedRectangle(cornerRadius: 13.638 * scale, style: .continuous)
                .fill(rightCapsule)
                .frame(width: 27.277 * scale, height: 49.911 * scale)
                .shadow(color: .black.opacity(shadowOpacity), radius: 4.643 * scale, y: 1.741 * scale)
                .offset(x: 26.12 * scale, y: 12.19 * scale)
        }
    }
}

struct RootHomeView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @EnvironmentObject private var pushNavigation: PushNavigationCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = Self.initialPath()
    @State private var activeSheet: HomeSheet?
    @State private var archiveCandidate: WalkGroup?
    @State private var archiveBlockedCandidate: WalkGroup?
    @State private var deleteCandidate: WalkGroup?
    @State private var pendingGroupAction: HomeGroupPendingAction?
    @State private var isShowingJoinSignInPrompt = false

    private static func initialPath() -> [Route] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-open-appstore-group") {
            return [.group("appstore-tokyo")]
        }
        #endif
        return []
    }

    private var activeGroups: [WalkGroup] {
        store.groups.filter { group in
            archiveIdentityIds.isDisjoint(with: Set(group.archivedUsers))
        }
    }

    private var archivedGroups: [WalkGroup] {
        store.groups.filter { group in
            !archiveIdentityIds.isDisjoint(with: Set(group.archivedUsers))
        }
    }

    private var archiveIdentityIds: Set<String> {
        var ids = Set<String>()
        ids.insert(store.localOwner.uuid)
        if let userId = store.user?.uuid {
            ids.insert(userId)
        }
        return ids
    }

    private var isBalanceAnimationEnabled: Bool {
        activeSheet == nil
            && archiveCandidate == nil
            && archiveBlockedCandidate == nil
            && deleteCandidate == nil
            && pendingGroupAction == nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                SoftLedgerBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if activeGroups.isEmpty, store.canLoadMoreGroups {
                            ProgressView()
                                .softLedgerProgressTint()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                                .task { await store.loadMoreGroups() }
                        } else if activeGroups.isEmpty {
                            GroupsEmptyState(
                                onCreateGroup: { activeSheet = .create },
                                onJoinGroup: { requestJoinGroup() }
                            )
                        } else {
                            HomeBalanceCard(isAnimationEnabled: isBalanceAnimationEnabled)
                            Text(L("All groups"))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.ink)
                                .padding(.top, 4)

                            LazyVStack(spacing: 16) {
                                ForEach(activeGroups) { group in
                                    Button {
                                        store.preloadGroupContent(group.id)
                                        path.append(.group(group.id))
                                    } label: {
                                        GroupSummaryRow(
                                            group: group,
                                            isPending: pendingGroupAction?.groupID == group.id,
                                            isAnimationEnabled: isBalanceAnimationEnabled
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(pendingGroupAction != nil)
                                    .onAppear {
                                        if group.id == activeGroups.last?.id {
                                            Task { await store.loadMoreGroups() }
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            archive(group)
                                        } label: {
                                            Label(L("Archive group"), systemImage: "archivebox")
                                        }
                                        .disabled(pendingGroupAction != nil)

                                        if group.canCurrentUserDelete {
                                            Button(role: .destructive) {
                                                deleteCandidate = group
                                            } label: {
                                                Label(L("Delete group"), systemImage: "trash")
                                            }
                                            .disabled(pendingGroupAction != nil)
                                        }
                                    }
                                }

                                if store.isLoadingMoreGroups {
                                    ProgressView()
                                        .softLedgerProgressTint()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
                .refreshable { await store.refreshHome() }
            }
            .navigationTitle(L("Groups"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .create
                        } label: {
                            Label(L("Create group"), systemImage: "person.2")
                        }

                        Button {
                            requestJoinGroup()
                        } label: {
                            Label(L("Join group"), systemImage: "person.2.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(L("Add group"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .archivedGroups
                        } label: {
                            Label(L("Archived groups"), systemImage: "archivebox")
                        }

                        Button {
                            activeSheet = .settings
                        } label: {
                            Label(L("Settings"), systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(L("Settings"))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .group(let id):
                    GroupView(groupId: id)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                NavigationStack {
                    CreateGroupSheet { groupId in
                        activeSheet = nil
                        store.preloadGroupContent(groupId)
                        path = [.group(groupId)]
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .join:
                NavigationStack {
                    JoinGroupSheet { activeSheet = nil }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            case .settings:
                NavigationStack {
                    SettingsSheet(archivedGroups: archivedGroups) {
                        activeSheet = nil
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .archivedGroups:
                NavigationStack {
                    ArchivedGroupsView(groups: archivedGroups)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .about:
                AboutSheet()
                    .presentationDetents([.medium])
            case .signIn:
                SignInSheet { activeSheet = nil }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert(L("Sign in required"), isPresented: $isShowingJoinSignInPrompt) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Sign in")) {
                activeSheet = .signIn
            }
        } message: {
            Text(L("Join group requires sign-in."))
        }
        .alert(L("Archive group?"), isPresented: Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } })) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Archive group")) {
                if let group = archiveCandidate {
                    Task { await archiveConfirmed(group) }
                }
                archiveCandidate = nil
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(L("Only groups with zero balances can be archived."))
        }
        .alert(L("Cannot archive group"), isPresented: Binding(get: { archiveBlockedCandidate != nil }, set: { if !$0 { archiveBlockedCandidate = nil } })) {
            Button(L("OK"), role: .cancel) {
                archiveBlockedCandidate = nil
            }
        } message: {
            Text(L("Settle all balances before archiving this group."))
        }
        .alert(L("Delete group?"), isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete group"), role: .destructive) {
                if let group = deleteCandidate {
                    Task { await deleteConfirmed(group) }
                }
                deleteCandidate = nil
            }
        } message: {
            if deleteCandidate?.shouldShowDeleteResolutionNotice == true {
                Text(L("Any unresolved balances will be automatically resolved to zero before this group is deleted."))
            }
        }
        .onOpenURL { url in
            guard url.scheme == "walkingcalc",
                  url.host == "group",
                  let code = url.pathComponents.dropFirst().first else {
                return
            }
            path.append(.group(code))
        }
        .task {
            await store.refreshHome()
        }
        .task(id: pushNavigation.pendingRequest?.id) {
            guard let request = pushNavigation.pendingRequest else { return }
            activeSheet = nil
            path = [.group(request.groupId)]
            await store.refreshGroupContent(request.groupId)
            pushNavigation.consume(request)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  let route = path.last,
                  case .group(let groupId) = route else {
                return
            }
            Task {
                await store.refreshGroupContent(groupId)
            }
        }
    }

    private func archive(_ group: WalkGroup) {
        if group.shouldBlockArchive {
            archiveBlockedCandidate = group
        } else {
            archiveCandidate = group
        }
    }

    private func archiveConfirmed(_ group: WalkGroup) async {
        guard pendingGroupAction == nil else { return }
        pendingGroupAction = .archive(group.id)
        _ = await store.archiveGroupWithFeedback(group.id)
        pendingGroupAction = nil
    }

    private func deleteConfirmed(_ group: WalkGroup) async {
        guard group.canCurrentUserDelete else { return }
        guard pendingGroupAction == nil else { return }
        pendingGroupAction = .delete(group.id)
        _ = await store.deleteGroupWithFeedback(group.id)
        pendingGroupAction = nil
    }

    private func requestJoinGroup() {
        if store.isLoggedIn {
            activeSheet = .join
        } else {
            isShowingJoinSignInPrompt = true
        }
    }
}

private enum HomeGroupPendingAction: Equatable {
    case archive(String)
    case delete(String)

    var groupID: String {
        switch self {
        case .archive(let groupID), .delete(let groupID):
            return groupID
        }
    }
}

private struct JoinGroupSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isGroupIDFocused: Bool

    let onDone: () -> Void
    @State private var groupID = ""
    @State private var joinErrorMessage: String?
    @State private var isSubmitting = false

    private var normalizedGroupID: String {
        groupID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canJoinGroup: Bool {
        !normalizedGroupID.isEmpty && !isSubmitting
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Group ID"), text: $groupID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isGroupIDFocused)
                    .softLedgerAccentTint()
                    .submitLabel(.join)
                    .onSubmit(submit)
                    .onChange(of: groupID) { _, newValue in
                        groupID = newValue.uppercased()
                        joinErrorMessage = nil
                    }
            } footer: {
                Text(joinErrorMessage ?? L("Enter the Group ID shared by another member."))
                    .foregroundStyle(joinErrorMessage == nil ? SoftLedgerTheme.secondaryInk : SoftLedgerTheme.negative)
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .navigationTitle(L("Join group"))
        .navigationBarTitleDisplayMode(.inline)
        .softLedgerDismissesKeyboardOnBackgroundTap(isActive: isGroupIDFocused) {
            isGroupIDFocused = false
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(L("Cancel"))
                .disabled(isSubmitting)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    submit()
                } label: {
                    AsyncConfirmationIcon(isPending: isSubmitting)
                }
                .buttonStyle(.borderedProminent)
                .softLedgerAccentTint()
                .disabled(!canJoinGroup)
                .accessibilityLabel(L("Join"))
            }
        }
        .onAppear {
            isGroupIDFocused = true
        }
    }

    private func submit() {
        guard canJoinGroup else { return }
        let code = normalizedGroupID
        joinErrorMessage = nil
        isSubmitting = true

        Task {
            let result = await store.joinGroupWithFeedback(code: code)
            if result.success {
                dismiss()
                onDone()
            } else {
                isSubmitting = false
                joinErrorMessage = result.message ?? L("No group matches this ID. Check it and try again.")
            }
        }
    }
}

private struct HomeBalanceCard: View {
    @EnvironmentObject private var store: WalkcalcStore

    let isAnimationEnabled: Bool

    private var actualCurrencyCodes: Set<String> {
        let identityIds = Set([store.localOwner.uuid, store.user?.uuid].compactMap { $0 })
        return store.groups.reduce(into: Set<String>()) { result, group in
            guard identityIds.isDisjoint(with: Set(group.archivedUsers)) else { return }
            let member = group.allMembers.first { identityIds.contains($0.uuid) }
            let projections = group.hasCurrentUserBalanceSummary
                ? group.currentUserCurrencyBalances
                : member?.currencyBalances ?? []
            for balance in projections where balance.hasLedgerActivity {
                result.insert(CurrencyCatalog.normalizedCode(balance.currencyCode))
            }
        }
    }

    private var balances: [CurrencyBalanceSummary] {
        let actualBalances = store.totalBalancesByCurrency.filter {
            actualCurrencyCodes.contains(CurrencyCatalog.normalizedCode($0.currencyCode))
                || !Money.isZero($0.totalBalanceMinor)
        }
        if !actualBalances.isEmpty {
            return actualBalances.sorted { $0.currencyCode < $1.currencyCode }
        }
        guard !Money.isZero(store.totalBalanceMinor) else { return [] }
        return [CurrencyBalanceSummary(
            currencyCode: CurrencyCatalog.defaultCurrencyCode(),
            totalBalanceMinor: store.totalBalanceMinor
        )]
    }

    private func scopeCount(for currencyCode: String) -> Int {
        let loadedCount = store.groups.filter {
            let identityIds = Set([store.localOwner.uuid, store.user?.uuid].compactMap { $0 })
            guard identityIds.isDisjoint(with: Set($0.archivedUsers)) else { return false }
            let member = $0.allMembers.first { identityIds.contains($0.uuid) }
            let currencyBalances = $0.hasCurrentUserBalanceSummary
                ? $0.currentUserCurrencyBalances
                : member?.currencyBalances ?? []
            let actualBalances = currencyBalances.filter(\.hasLedgerActivity)
            if actualBalances.isEmpty {
                let legacyBalance = $0.hasCurrentUserBalanceSummary
                    ? $0.currentUserBalanceMinor
                    : member?.debtMinor ?? "0"
                guard !Money.isZero(legacyBalance) else { return false }
                return CurrencyCatalog.normalizedCode($0.currencyCode) == currencyCode
            }
            return actualBalances.contains {
                CurrencyCatalog.normalizedCode($0.currencyCode) == currencyCode
            }
        }.count
        return loadedCount > 0 ? loadedCount : max(store.groupTotal, store.groups.count)
    }

    var body: some View {
        SoftLedgerCard(usesGlass: true) {
            if balances.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Total balance"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    Text("—")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(SoftLedgerTheme.ink)
                }
            } else {
                CurrencyBalanceCarousel(
                    balances: balances,
                    isAnimationEnabled: isAnimationEnabled,
                    scopeCount: scopeCount
                )
            }
        }
    }
}

struct CurrencyBalanceCarousel: View {
    private enum Direction: Int {
        case previous = -1
        case next = 1
    }

    private enum Presentation {
        case card
        case compact
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var cardAmountPageHeight = 52
    @ScaledMetric(relativeTo: .subheadline) private var compactAmountPageHeight = 24

    let balances: [CurrencyBalanceSummary]
    let isAnimationEnabled: Bool
    private let title: String
    let scopeCount: ((String) -> Int)?
    let subtitle: ((CurrencyBalanceSummary) -> String)?
    let onTap: ((CurrencyBalanceSummary) -> Void)?
    private let presentation: Presentation
    private let amountColor: (CurrencyBalanceSummary) -> Color

    @State private var selection = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isSettling = false
    @State private var hasUserInteracted = false
    @State private var settleTask: Task<Void, Never>?

    init(
        balances: [CurrencyBalanceSummary],
        isAnimationEnabled: Bool,
        scopeCount: @escaping (String) -> Int
    ) {
        self.balances = balances
        self.isAnimationEnabled = isAnimationEnabled
        self.title = L("Total balance")
        self.scopeCount = scopeCount
        self.subtitle = nil
        self.onTap = nil
        self.presentation = .card
        self.amountColor = { _ in SoftLedgerTheme.ink }
    }

    init(
        balances: [CurrencyBalanceSummary],
        isAnimationEnabled: Bool,
        subtitle: @escaping (CurrencyBalanceSummary) -> String,
        onTap: @escaping (CurrencyBalanceSummary) -> Void
    ) {
        self.balances = balances
        self.isAnimationEnabled = isAnimationEnabled
        self.title = L("Total balance")
        self.scopeCount = nil
        self.subtitle = subtitle
        self.onTap = onTap
        self.presentation = .card
        self.amountColor = { _ in SoftLedgerTheme.ink }
    }

    init(
        balances: [CurrencyBalanceSummary],
        isAnimationEnabled: Bool,
        title: String,
        amountColor: @escaping (CurrencyBalanceSummary) -> Color
    ) {
        self.balances = balances
        self.isAnimationEnabled = isAnimationEnabled
        self.title = title
        self.scopeCount = nil
        self.subtitle = nil
        self.onTap = nil
        self.presentation = .card
        self.amountColor = amountColor
    }

    init(
        compactBalances balances: [CurrencyBalanceSummary],
        isAnimationEnabled: Bool,
        amountColor: @escaping (CurrencyBalanceSummary) -> Color
    ) {
        self.balances = balances
        self.isAnimationEnabled = isAnimationEnabled
        self.title = ""
        self.scopeCount = nil
        self.subtitle = nil
        self.onTap = nil
        self.presentation = .compact
        self.amountColor = amountColor
    }

    private var selectedBalance: CurrencyBalanceSummary {
        balances[safe: selection] ?? balances[0]
    }

    private var selectedScopeCount: Int {
        scopeCount?(selectedBalance.currencyCode) ?? 0
    }

    private var autoPlayID: String {
        let identities = balances.map { "\($0.currencyCode):\($0.totalBalanceMinor)" }.joined(separator: "|")
        return "\(identities)-\(hasUserInteracted)-\(isAnimationEnabled)-\(scenePhase == .active)"
    }

    private var allowsNumericAnimation: Bool {
        isAnimationEnabled && !isSettling && dragOffset == 0
    }

    private var amountPageHeight: CGFloat {
        presentation == .card ? cardAmountPageHeight : compactAmountPageHeight
    }

    private var contentMaxWidth: CGFloat? {
        presentation == .card ? .infinity : nil
    }

    var body: some View {
        carouselContent
            .frame(maxWidth: contentMaxWidth, alignment: presentation == .card ? .leading : .trailing)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?(selectedBalance)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(onTap == nil ? "" : L("View details"))
            .accessibilityValue(balances.count > 1 ? "\(selection + 1) / \(balances.count)" : "")
            .accessibilityAdjustableAction { direction in
                guard balances.count > 1 else { return }
                stopAutoPlay()
                switch direction {
                case .increment:
                    settle(.next, pageHeight: amountPageHeight)
                case .decrement:
                    settle(.previous, pageHeight: amountPageHeight)
                @unknown default:
                    break
                }
            }
            .task(id: autoPlayID) {
                guard balances.count > 1,
                      !hasUserInteracted,
                      isAnimationEnabled,
                      scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled,
                          !hasUserInteracted,
                          !isSettling,
                          isAnimationEnabled,
                          scenePhase == .active else { return }
                    settle(.next, pageHeight: amountPageHeight)
                }
            }
            .onChange(of: balances.map(\.currencyCode)) { oldCodes, newCodes in
                guard oldCodes != newCodes else { return }
                let selectedCode = oldCodes[safe: selection]
                selection = selectedCode.flatMap { newCodes.firstIndex(of: $0) } ?? 0
                dragOffset = 0
                isSettling = false
                settleTask?.cancel()
            }
            .onDisappear {
                settleTask?.cancel()
            }
            .allowsHitTesting(presentation == .card)
    }

    @ViewBuilder
    private var carouselContent: some View {
        if presentation == .compact {
            amountViewport
        } else {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)

                    HStack(alignment: .center, spacing: 12) {
                        amountViewport

                        if balances.count > 1 {
                            CurrencyPageIndicator(
                                pageCount: balances.count,
                                selection: selection
                            )
                            .offset(x: 6)
                        }
                    }
                }

                if let subtitle {
                    Text(subtitle(selectedBalance))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                } else if scopeCount != nil {
                    AnimatedGroupScopeText(groupCount: selectedScopeCount)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .lineLimit(1)
                }
            }
        }
    }

    private var amountViewport: some View {
        GeometryReader { geometry in
            let height = max(geometry.size.height, 1)
            if balances.count > 1 {
                ZStack {
                    balancePage(balance(at: .previous))
                        .modifier(CurrencyCylinderRollEffect(
                            position: (-height + dragOffset) / height,
                            travelHeight: height,
                            reduceMotion: reduceMotion
                        ))

                    balancePage(selectedBalance)
                        .modifier(CurrencyCylinderRollEffect(
                            position: dragOffset / height,
                            travelHeight: height,
                            reduceMotion: reduceMotion
                        ))

                    balancePage(balance(at: .next))
                        .modifier(CurrencyCylinderRollEffect(
                            position: (height + dragOffset) / height,
                            travelHeight: height,
                            reduceMotion: reduceMotion
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .highPriorityGesture(dragGesture(pageHeight: height))
            } else {
                balancePage(selectedBalance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: amountPageHeight)
    }

    private func balancePage(_ balance: CurrencyBalanceSummary) -> some View {
        Group {
            if presentation == .compact {
                Text(signedMoney(balance.totalBalanceMinor, currencyCode: balance.currencyCode))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(amountColor(balance))
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            } else {
                AnimatedBalanceAmountText(
                    amountMinor: balance.totalBalanceMinor,
                    style: .exact,
                    currencyCode: balance.currencyCode,
                    isAnimationEnabled: allowsNumericAnimation,
                    foregroundColor: amountColor(balance)
                )
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .id(balance.currencyCode)
    }

    private func balance(at direction: Direction) -> CurrencyBalanceSummary {
        guard balances.count > 1 else { return selectedBalance }
        let index = (selection + direction.rawValue + balances.count) % balances.count
        return balances[index]
    }

    private func dragGesture(pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard balances.count > 1,
                      !isSettling,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                stopAutoPlay()
                dragOffset = interactiveDragOffset(value.translation.height, pageHeight: pageHeight)
            }
            .onEnded { value in
                guard balances.count > 1, !isSettling else { return }
                let projectedOffset = value.predictedEndTranslation.height
                let threshold = pageHeight * 0.24
                if projectedOffset <= -threshold {
                    settle(.next, pageHeight: pageHeight)
                } else if projectedOffset >= threshold {
                    settle(.previous, pageHeight: pageHeight)
                } else {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func stopAutoPlay() {
        if !hasUserInteracted {
            hasUserInteracted = true
        }
    }

    private func interactiveDragOffset(_ translation: CGFloat, pageHeight: CGFloat) -> CGFloat {
        let direction: CGFloat = translation < 0 ? -1 : 1
        let distance = abs(translation)
        let linearLimit = pageHeight * 0.56
        guard distance > linearLimit else { return translation }
        let resistedDistance = linearLimit + (distance - linearLimit) * 0.24
        return direction * min(resistedDistance, pageHeight * 0.8)
    }

    private func settle(_ direction: Direction, pageHeight: CGFloat) {
        guard balances.count > 1, !isSettling else { return }
        settleTask?.cancel()

        if reduceMotion {
            selection = (selection + direction.rawValue + balances.count) % balances.count
            dragOffset = 0
            return
        }

        isSettling = true
        let targetOffset = direction == .next ? -pageHeight : pageHeight
        withAnimation(.spring(duration: 0.46, bounce: 0.08)) {
            dragOffset = targetOffset
        }

        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(460))
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selection = (selection + direction.rawValue + balances.count) % balances.count
                dragOffset = 0
                isSettling = false
            }
        }
    }

    private var accessibilityLabel: String {
        var components = [title, signedMoney(selectedBalance.totalBalanceMinor, style: .exact, currencyCode: selectedBalance.currencyCode)]
        if let subtitle {
            components.append(subtitle(selectedBalance))
        } else if scopeCount != nil {
            components.append(groupScopeText(selectedScopeCount))
        }
        return components.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct AnimatedGroupScopeText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let groupCount: Int

    @State private var displayedCount: Int?
    @State private var isPulsing = false
    @State private var transitionTask: Task<Void, Never>?

    private var resolvedCount: Int {
        displayedCount ?? groupCount
    }

    var body: some View {
        Text(groupScopeText(resolvedCount))
            .contentTransition(.numericText(value: Double(resolvedCount)))
            .scaleEffect(isPulsing ? 1.018 : 1, anchor: .leading)
            .offset(y: isPulsing ? -1 : 0)
            .onAppear {
                displayedCount = groupCount
            }
            .onChange(of: groupCount) { _, newCount in
                animateCount(to: newCount)
            }
            .onDisappear {
                transitionTask?.cancel()
            }
    }

    private func animateCount(to newCount: Int) {
        transitionTask?.cancel()

        guard !reduceMotion else {
            displayedCount = newCount
            isPulsing = false
            return
        }

        transitionTask = Task { @MainActor in
            // Currency selection is committed without animation after the page
            // settles, so start this numeric transition on the next run-loop turn.
            await Task.yield()
            guard !Task.isCancelled else { return }

            withAnimation(.snappy(duration: 0.34)) {
                displayedCount = newCount
                isPulsing = true
            }

            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.22)) {
                isPulsing = false
            }
        }
    }
}

private func groupScopeText(_ count: Int) -> String {
    if count == 1 {
        return L("Across 1 group")
    }
    return L("Across %@ groups").replacingOccurrences(of: "%@", with: "\(count)")
}

private struct CurrencyPageIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let pageCount: Int
    let selection: Int

    @State private var displayedPosition = 0
    @State private var transitionTask: Task<Void, Never>?

    private var visibleCount: Int {
        min(pageCount, 3)
    }

    private var position: Int {
        if visibleCount <= 1 {
            return 0
        }
        if pageCount == 2 {
            return min(max(selection, 0), 1)
        }
        if selection <= 0 {
            return 0
        }
        if selection >= pageCount - 1 {
            return 2
        }
        return 1
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<visibleCount, id: \.self) { index in
                Circle()
                    .fill(SoftLedgerTheme.ink)
                    .frame(width: 5, height: 5)
                    .opacity(index == displayedPosition ? 0.72 : 0.18)
            }
        }
        .onAppear {
            displayedPosition = position
        }
        .onChange(of: position) { _, newPosition in
            transition(to: newPosition)
        }
        .onDisappear {
            transitionTask?.cancel()
        }
        .accessibilityHidden(true)
    }

    private func transition(to newPosition: Int) {
        transitionTask?.cancel()

        guard !reduceMotion else {
            displayedPosition = newPosition
            return
        }

        transitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                displayedPosition = newPosition
            }
        }
    }
}

private struct CurrencyCylinderRollEffect: ViewModifier {
    let position: CGFloat
    let travelHeight: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let direction: CGFloat = position < 0 ? -1 : 1
        let absolutePosition = abs(position)
        let progress = min(absolutePosition, 1)
        let overflow = max(absolutePosition - 1, 0)
        let angle = progress * .pi * 0.38
        let cylinderRadius = travelHeight * 0.78
        let arcOffset = sin(angle) * cylinderRadius
        let verticalOffset = direction * (arcOffset + overflow * travelHeight * 0.78)
        let depthScale = reduceMotion ? 1 : 1 - (1 - cos(angle)) * 0.34
        let blurRadius = reduceMotion ? 0 : pow(progress, 1.4) * 3.2

        content
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : -Double(direction * progress) * 68),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                perspective: 0.68
            )
            .scaleEffect(depthScale)
            .blur(radius: blurRadius)
            .opacity(max(0.16, 1 - Double(pow(progress, 1.2)) * 0.84))
            .offset(y: reduceMotion ? position * travelHeight : verticalOffset)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct GroupSummaryRow: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .caption) private var memberAvatarSize = 24
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 72
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding = 14
    @ScaledMetric(relativeTo: .subheadline) private var verticalPadding = 10
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius = 16
    @ScaledMetric(relativeTo: .caption) private var titleSpacing = 6
    @ScaledMetric(relativeTo: .caption) private var metadataSpacing = 8
    @ScaledMetric(relativeTo: .caption) private var statusInset = 12
    @ScaledMetric(relativeTo: .caption) private var statusWidth = 3
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth = 82
    @ScaledMetric(relativeTo: .subheadline) private var amountHeight = 24

    let group: WalkGroup
    let isPending: Bool
    let isAnimationEnabled: Bool

    private var myBalance: MoneyMinor {
        if group.hasCurrentUserBalanceSummary {
            return group.currentUserBalanceMinor
        }
        return group.membersInfo.first(where: { $0.uuid == store.user?.uuid })?.debtMinor ?? group.currentUserBalanceMinor
    }

    private var displayMembers: [Member] {
        group.allMembers.isEmpty ? group.participantPreview : group.allMembers
    }

    private var currentMember: Member? {
        guard let participantID = store.currentParticipantID(for: group) else { return nil }
        return group.allMembers.first { $0.uuid == participantID }
    }

    private var carouselBalances: [CurrencyBalanceSummary] {
        let projections = group.hasCurrentUserBalanceSummary
            ? group.currentUserCurrencyBalances
            : currentMember?.currencyBalances ?? []
        let actualBalances = projections
            .filter(\.hasLedgerActivity)
            .sorted { $0.currencyCode < $1.currencyCode }
        if !actualBalances.isEmpty {
            return actualBalances.map {
                CurrencyBalanceSummary(
                    currencyCode: $0.currencyCode,
                    totalBalanceMinor: $0.debtMinor
                )
            }
        }
        guard !Money.isZero(myBalance) else { return [] }
        return [CurrencyBalanceSummary(
            currencyCode: CurrencyCatalog.normalizedCode(group.currencyCode),
            totalBalanceMinor: myBalance
        )]
    }

    private var accessibilityBalanceText: String {
        guard !carouselBalances.isEmpty else { return "—" }
        return carouselBalances
            .map { signedMoney($0.totalBalanceMinor, currencyCode: $0.currencyCode) }
            .joined(separator: ", ")
    }

    private var balanceIndicatorColor: Color {
        moneyColor(myBalance).opacity(Money.isZero(myBalance) ? 0.32 : 0.58)
    }

    var body: some View {
        HStack(spacing: rowSpacing) {
            VStack(alignment: .leading, spacing: titleSpacing) {
                Text(group.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: metadataSpacing) {
                    SoftLedgerAvatarStack(members: displayMembers, visibleCount: 3, size: memberAvatarSize, showsTotal: false)
                }
            }
            .layoutPriority(1)

            Spacer()

            if carouselBalances.isEmpty {
                Text("—")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    .frame(width: amountWidth, height: amountHeight, alignment: .trailing)
                    .layoutPriority(2)
            } else {
                CurrencyBalanceCarousel(
                    compactBalances: carouselBalances,
                    isAnimationEnabled: isAnimationEnabled,
                    amountColor: { moneyColor($0.totalBalanceMinor) }
                )
                .frame(width: amountWidth, height: amountHeight, alignment: .trailing)
                .layoutPriority(2)
            }

            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .softLedgerProgressTint()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(balanceIndicatorColor)
                .frame(width: statusWidth)
                .padding(.vertical, statusInset)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(accessibilityBalanceText)")
        .accessibilityHint(L("Opens group details"))
    }
}

private struct GroupsEmptyState: View {
    let onCreateGroup: () -> Void
    let onJoinGroup: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .softLedgerAccentForeground()
                .frame(width: 64, height: 64)
                .background(SoftLedgerTheme.paper, in: Circle())
                .overlay {
                    Circle().stroke(SoftLedgerTheme.rule.opacity(0.65), lineWidth: 1)
                }

            VStack(spacing: 6) {
                Text(L("No groups yet"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.ink)
                Text(L("Create a group or join one shared by friends, roommates, or a trip."))
                    .font(.callout)
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    onCreateGroup()
                } label: {
                    Label(L("Create group"), systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)

                if let onJoinGroup {
                    Button {
                        onJoinGroup()
                    } label: {
                        Label(L("Join group"), systemImage: "person.2.badge.plus")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}

private struct AboutSheet: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 58))
                .softLedgerAccentForeground()
            Text("Walking Calculator")
                .font(.title3.bold())
            Text(L("Expense splitting for groups, trips, and daily costs."))
                .foregroundStyle(SoftLedgerTheme.secondaryInk)
        }
        .padding(24)
        .background(SoftLedgerBackground())
    }
}

#Preview {
    ContentView()
        .environmentObject(WalkcalcStore())
}
