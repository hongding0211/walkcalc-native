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

    var id: String {
        switch self {
        case .create: "create"
        case .join: "join"
        case .settings: "settings"
        case .archivedGroups: "archivedGroups"
        case .about: "about"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: WalkcalcStore

    var body: some View {
        Group {
            switch store.startupRoute {
            case .resolving:
                LaunchGateView()
            case .authenticated:
                RootHomeView()
            case .loginRequired:
                LoginView()
            }
        }
        .task {
            await store.prepareNetworkAccessForStartup()
            await store.bootstrap()
            await store.requestNotificationPermissionIfNeeded()
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
                    .offset(x: layout.x(16), y: layout.y(308))

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

    var body: some View {
        LoginScreen(isSigningIn: store.isSigningIn) {
            showingSSO = true
        }
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
}

private struct LoginScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let isSigningIn: Bool
    let onLogin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = LoginLayout(size: proxy.size)
            let markScale = layout.scale * 1.08

            ZStack(alignment: .topLeading) {
                loginBackground
                    .ignoresSafeArea()

                LoginBrandMark(scale: markScale)
                    .frame(width: layout.value(70.2), height: layout.value(80.229))
                    .offset(x: layout.x(16), y: layout.y(308))

                Text("Walking Calculator")
                    .font(.system(size: layout.value(21), weight: .semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: layout.value(310), alignment: .leading)
                    .lineLimit(1)
                    .offset(x: layout.x(42), y: layout.y(412))

                Text(L("Login to continue"))
                    .font(.custom("PingFangSC-Medium", size: layout.value(15)))
                    .foregroundStyle(secondaryText)
                    .frame(width: layout.value(260), alignment: .leading)
                    .lineLimit(1)
                    .offset(x: layout.x(42), y: layout.y(446))

                Button(action: onLogin) {
                    HStack(spacing: layout.value(8)) {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                                .tint(buttonForeground)
                        }
                        Text(L("Login"))
                    }
                    .font(.system(size: layout.value(17), weight: .semibold))
                    .foregroundStyle(buttonForeground)
                    .frame(width: layout.value(318), height: layout.value(52))
                    .background(buttonBackground, in: RoundedRectangle(cornerRadius: layout.value(17), style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.12), radius: layout.value(18), y: layout.value(8))
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .offset(x: layout.x(36), y: layout.y(708))
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

    private var buttonBackground: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0xF4F4F0)) : Color(UIColor(hex: 0x050505))
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? Color(UIColor(hex: 0x050505)) : .white
    }
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
        colorScheme == .dark ? Color(UIColor(hex: 0xF8F8F5)) : .white
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
    @State private var path: [Route] = Self.initialPath()
    @State private var activeSheet: HomeSheet?
    @State private var archiveCandidate: WalkGroup?
    @State private var archiveBlockedCandidate: WalkGroup?
    @State private var deleteCandidate: WalkGroup?
    @State private var pendingGroupAction: HomeGroupPendingAction?

    private static func initialPath() -> [Route] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-open-appstore-group") {
            return [.group("appstore-tokyo")]
        }
        #endif
        return []
    }

    private var activeGroups: [WalkGroup] {
        guard let user = store.user else { return store.groups }
        return store.groups.filter { !$0.archivedUsers.contains(user.uuid) }
    }

    private var archivedGroups: [WalkGroup] {
        guard let user = store.user else { return [] }
        return store.groups.filter { $0.archivedUsers.contains(user.uuid) }
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
                                onJoinGroup: { activeSheet = .join }
                            )
                        } else {
                            HomeBalanceCard()
                            Text(L("All groups"))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.ink)
                                .padding(.top, 4)

                            LazyVStack(spacing: 16) {
                                ForEach(activeGroups) { group in
                                    NavigationLink(value: Route.group(group.id)) {
                                        GroupSummaryRow(group: group, isPending: pendingGroupAction?.groupID == group.id)
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

                                        Button(role: .destructive) {
                                            deleteCandidate = group
                                        } label: {
                                            Label(L("Delete group"), systemImage: "trash")
                                        }
                                        .disabled(pendingGroupAction != nil)
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
                            activeSheet = .join
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
                    CreateGroupSheet { activeSheet = nil }
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
            }
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
        guard pendingGroupAction == nil else { return }
        pendingGroupAction = .delete(group.id)
        _ = await store.deleteGroupWithFeedback(group.id)
        pendingGroupAction = nil
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

    private var scopeText: String {
        let count = max(store.groupTotal, store.groups.count)
        if count == 1 {
            return L("Across 1 group")
        }
        return L("Across %@ groups").replacingOccurrences(of: "%@", with: "\(count)")
    }

    var body: some View {
        SoftLedgerCard(usesGlass: true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Total balance"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    Text(signedMoney(store.totalBalanceMinor, style: .exact))
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(scopeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
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
    @ScaledMetric(relativeTo: .subheadline) private var amountMinWidth = 82

    let group: WalkGroup
    let isPending: Bool

    private var myBalance: MoneyMinor {
        if group.hasCurrentUserBalanceSummary {
            return group.currentUserBalanceMinor
        }
        return group.membersInfo.first(where: { $0.uuid == store.user?.uuid })?.debtMinor ?? group.currentUserBalanceMinor
    }

    private var displayMembers: [Member] {
        group.allMembers.isEmpty ? group.participantPreview : group.allMembers
    }

    private var balanceTextColor: Color {
        Money.isZero(myBalance) ? SoftLedgerTheme.ink : moneyColor(myBalance)
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

            Text(signedMoney(myBalance))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(balanceTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .frame(minWidth: amountMinWidth, alignment: .trailing)
                .layoutPriority(2)

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
        .accessibilityLabel("\(group.name), \(signedMoney(myBalance))")
        .accessibilityHint(L("Opens group details"))
    }
}

private struct GroupsEmptyState: View {
    let onCreateGroup: () -> Void
    let onJoinGroup: () -> Void

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

                Button {
                    onJoinGroup()
                } label: {
                    Label(L("Join group"), systemImage: "person.2.badge.plus")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
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
