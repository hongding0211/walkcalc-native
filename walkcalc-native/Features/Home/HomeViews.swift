import SwiftUI

enum Route: Hashable {
    case group(String)
}

enum HomeSheet: Identifiable {
    case create
    case settings
    case archivedGroups
    case about

    var id: String {
        switch self {
        case .create: "create"
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
            if store.isBootstrapping {
                ZStack {
                    SoftLedgerBackground()
                    ProgressView()
                }
            } else if store.isLoggedIn {
                RootHomeView()
            } else {
                LoginView()
            }
        }
        .task {
            await store.requestNotificationPermissionIfNeeded()
            await store.bootstrap()
        }
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.10).ignoresSafeArea()
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .alert(L("Notice"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(L("Confirm"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @State private var showingSSO = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(SoftLedgerTheme.accent)
                Text("Walking Calculator")
                    .font(.title.bold())
                    .foregroundStyle(SoftLedgerTheme.ink)
                Text(L("Login"))
                    .font(.subheadline)
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
            }
            Spacer()
            Button {
                showingSSO = true
            } label: {
                Text(L("Login"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(SoftLedgerTheme.accent)
            .padding(.bottom, 24)
        }
        .padding(24)
        .background(SoftLedgerBackground())
        .sheet(isPresented: $showingSSO) {
            SSOLoginView { token in
                showingSSO = false
                Task {
                    await store.signIn(token: token)
                }
            }
        }
    }
}

struct RootHomeView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @State private var path: [Route] = []
    @State private var activeSheet: HomeSheet?
    @State private var isJoiningGroup = false
    @State private var joinGroupID = ""
    @State private var archiveCandidate: WalkGroup?
    @State private var deleteCandidate: WalkGroup?

    private var activeGroups: [WalkGroup] {
        guard let user = store.user else { return store.groups }
        return store.groups.filter { !$0.archivedUsers.contains(user.uuid) }
    }

    private var archivedGroups: [WalkGroup] {
        guard let user = store.user else { return [] }
        return store.groups.filter { $0.archivedUsers.contains(user.uuid) }
    }

    private var canJoinGroup: Bool {
        !joinGroupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                SoftLedgerBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if activeGroups.isEmpty, store.canLoadMoreGroups {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                                .task { await store.loadMoreGroups() }
                        } else if activeGroups.isEmpty {
                            GroupsEmptyState(
                                onCreateGroup: { activeSheet = .create },
                                onJoinGroup: { isJoiningGroup = true }
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
                                        GroupSummaryRow(group: group)
                                    }
                                    .buttonStyle(.plain)
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

                                        Button(role: .destructive) {
                                            deleteCandidate = group
                                        } label: {
                                            Label(L("Delete group"), systemImage: "trash")
                                        }
                                    }
                                }

                                if store.isLoadingMoreGroups {
                                    ProgressView()
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
                            isJoiningGroup = true
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
        .alert(L("Join group"), isPresented: $isJoiningGroup) {
            TextField(L("Group ID"), text: $joinGroupID)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: joinGroupID) { _, newValue in
                    joinGroupID = newValue.uppercased()
                }

            Button(L("Cancel"), role: .cancel) {
                joinGroupID = ""
            }

            Button(L("Join")) {
                let code = joinGroupID.trimmingCharacters(in: .whitespacesAndNewlines)
                joinGroupID = ""
                Task { _ = await store.joinGroup(code: code) }
            }
            .disabled(!canJoinGroup)
        }
        .alert(L("Archive group?"), isPresented: Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } })) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Archive group")) {
                if let group = archiveCandidate {
                    Task { _ = await store.archiveGroup(group.id) }
                }
                archiveCandidate = nil
            }
            .keyboardShortcut(.defaultAction)
        }
        .alert(L("Delete group?"), isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete group"), role: .destructive) {
                if let group = deleteCandidate {
                    Task { _ = await store.deleteGroup(group.id) }
                }
                deleteCandidate = nil
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
        archiveCandidate = group
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

    private var myBalance: MoneyMinor {
        if group.hasCurrentUserBalanceSummary {
            return group.currentUserBalanceMinor
        }
        return group.membersInfo.first(where: { $0.uuid == store.user?.uuid })?.debtMinor ?? group.currentUserBalanceMinor
    }

    private var memberCountText: String {
        L("%@ members").replacingOccurrences(of: "%@", with: "\(displayMemberCount)")
    }

    private var displayMembers: [Member] {
        group.allMembers.isEmpty ? group.participantPreview : group.allMembers
    }

    private var displayMemberCount: Int {
        if group.participantCount > 0 {
            return group.participantCount
        }
        return displayMembers.count
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
                    Text(memberCountText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .lineLimit(1)
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

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
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
        .accessibilityLabel("\(group.name), \(signedMoney(myBalance)), \(memberCountText)")
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
                .foregroundStyle(SoftLedgerTheme.accent)
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
                .foregroundStyle(SoftLedgerTheme.accent)
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
