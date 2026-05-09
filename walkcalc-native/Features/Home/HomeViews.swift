import SwiftUI

enum Route: Hashable {
    case group(String)
    case archived
    case settings
}

struct ContentView: View {
    @EnvironmentObject private var store: WalkcalcStore

    var body: some View {
        Group {
            if store.isBootstrapping {
                ProgressView()
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
        .tint(store.primaryColor)
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(store.primaryColor)
                Text("Walking Calculator")
                    .font(.title.bold())
                Text(L("Login to continue"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingSSO = true
            } label: {
                Text(L("Continue with hong97.ltd"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .padding(24)
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

    var unarchivedGroups: [WalkGroup] {
        guard let user = store.user else { return store.groups }
        return store.groups.filter { !$0.archivedUsers.contains(user.uuid) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AppBackground()
                List {
                    HomeHeader(
                        onAdd: { activeSheet = .addChoice },
                        onSettings: { path.append(.settings) },
                        onAbout: { activeSheet = .about }
                    )
                    .listRowChrome(top: 18)

                    TotalDebtCard(total: store.totalDebtMinor())
                        .listRowChrome()

                    HStack {
                        Text("\(L("All Groups")) (\(store.groups.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            path.append(.archived)
                        } label: {
                            Image(systemName: "archivebox")
                        }
                        .disabled(store.groups.count == unarchivedGroups.count)
                    }
                    .padding(.horizontal, 8)
                    .listRowChrome()

                    ForEach(unarchivedGroups) { group in
                        NavigationLink(value: Route.group(group.id)) {
                            GroupSummaryCard(group: group)
                        }
                        .buttonStyle(.plain)
                        .listRowChrome(bottom: 14)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(L("Archive"), systemImage: "archivebox") {
                                Task { _ = await store.archiveGroup(group.id) }
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.refreshHome() }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .group(let id):
                    GroupView(groupId: id)
                case .archived:
                    ArchivedView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            HomeSheetView(sheet: sheet, activeSheet: $activeSheet)
        }
        .onOpenURL { url in
            guard url.scheme == "walkingcalc",
                  url.host == "group",
                  let code = url.pathComponents.dropFirst().first else {
                return
            }
            path.append(.group(code))
        }
    }
}

enum HomeSheet: Identifiable {
    case addChoice
    case create
    case join
    case about

    var id: String {
        switch self {
        case .addChoice: "addChoice"
        case .create: "create"
        case .join: "join"
        case .about: "about"
        }
    }
}

struct HomeSheetView: View {
    @EnvironmentObject private var store: WalkcalcStore
    let sheet: HomeSheet
    @Binding var activeSheet: HomeSheet?
    @State private var text = ""
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch sheet {
                case .addChoice:
                    Button(L("New group"), systemImage: "plus.circle") { activeSheet = .create }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button(L("Join group"), systemImage: "person.2.badge.plus") { activeSheet = .join }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                case .create:
                    TextField(L("Group name"), text: $text)
                        .textFieldStyle(.roundedBorder)
                    Button(L("Confirm")) {
                        Task {
                            if await store.createGroup(name: text) {
                                activeSheet = nil
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                case .join:
                    TextField(L("Group ID"), text: $text)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .onChange(of: text) { _, newValue in
                            text = newValue.uppercased()
                        }
                    Button(L("Scan to join"), systemImage: "viewfinder") {
                        showScanner = true
                    }
                    .buttonStyle(.bordered)
                    Button(L("Confirm join")) {
                        Task {
                            if await store.joinGroup(code: text) {
                                activeSheet = nil
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                case .about:
                    VStack(spacing: 10) {
                        Image(systemName: "figure.walk.circle.fill")
                            .font(.system(size: 58))
                            .foregroundStyle(store.primaryColor)
                        Text("Walking Calculator")
                            .font(.title3.bold())
                        Text(L("Expense splitting for groups, trips, and daily costs."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.medium])
        .fullScreenCover(isPresented: $showScanner) {
            NavigationStack {
                QRScannerView { result in
                    if let code = groupCode(from: result) {
                        text = code
                    }
                    showScanner = false
                }
                .navigationTitle(L("Scan to join"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Cancel")) { showScanner = false }
                    }
                }
            }
        }
    }

    private var title: String {
        switch sheet {
        case .addChoice: ""
        case .create: L("New group")
        case .join: L("Join group")
        case .about: L("About")
        }
    }

    private func groupCode(from value: String) -> String? {
        guard let url = URL(string: value),
              url.scheme == "walkingcalc",
              url.host == "group",
              let code = url.pathComponents.dropFirst().first else {
            return nil
        }
        return code
    }
}

struct HomeHeader: View {
    @EnvironmentObject private var store: WalkcalcStore
    var onAdd: () -> Void
    var onSettings: () -> Void
    var onAbout: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text(L("Group"))
                    .font(.system(size: 36, weight: .bold))
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .onTapGesture(perform: onAdd)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("Group"))
            .accessibilityAddTraits(.isButton)
            Spacer()
            Menu {
                Button(L("Settings"), systemImage: "gearshape", action: onSettings)
                Button(L("About"), systemImage: "info.circle", action: onAbout)
                Button(L("Logout"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    store.logout()
                }
            } label: {
                AvatarView(user: store.user)
            }
        }
        .padding(.top, 18)
    }
}

struct TotalDebtCard: View {
    var total: MoneyMinor

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    Image(systemName: "wallet.pass.fill")
                    Text(L("Total Debt"))
                        .font(.title2.weight(.medium))
                }
                .foregroundStyle(Money.isNegative(total) ? Color.red : Color.green)
                Text("\(Money.isNegative(total) ? "" : "+")\(Money.display(total))")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct GroupSummaryCard: View {
    @EnvironmentObject private var store: WalkcalcStore
    var group: WalkGroup

    var myDebt: MoneyMinor {
        group.membersInfo.first(where: { $0.uuid == store.user?.uuid })?.debtMinor ?? "0"
    }

    var body: some View {
        CardContainer {
            VStack(spacing: 30) {
                HStack {
                    Text(group.name)
                        .font(.title2.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Label("\(group.allMembers.count)", systemImage: "person.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(store.primaryColor)
                }
                HStack {
                    StackText(top: L("Latest edited"), bottom: DateFormatter.walkDate.string(from: group.modifiedAt.walkDate), alignment: .leading)
                    Spacer()
                    StackText(top: Money.isNegative(myDebt) ? L("I owed") : L("Owed to me"), bottom: "\(Money.isNegative(myDebt) ? "" : "+")\(Money.display(myDebt))", alignment: .trailing)
                }
            }
        }
    }
}

struct ArchivedView: View {
    @EnvironmentObject private var store: WalkcalcStore

    var archivedGroups: [WalkGroup] {
        guard let user = store.user else { return [] }
        return store.groups.filter { $0.archivedUsers.contains(user.uuid) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                ForEach(archivedGroups) { group in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(group.name)
                            Text(group.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Unarchive")) {
                            Task { _ = await store.unarchiveGroup(group.id) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L("Archived Groups"))
        .task { await store.refreshHome() }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @State private var confirmLogout = false
    @State private var showingProfile = false

    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section(L("User")) {
                    HStack(spacing: 10) {
                        AvatarView(user: store.user, size: 28)
                        Text(store.user?.name ?? "")
                    }
                    Button(L("Edit Profile")) { showingProfile = true }
                }
                Section(L("General")) {
                    HStack {
                        Text(L("Theme Color"))
                        Spacer()
                        ForEach(themeColorOptions) { option in
                            Button {
                                store.setThemeColor(option.id)
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if option.id == store.themeColorId {
                                            Circle().stroke(store.primaryColor, lineWidth: 3).frame(width: 34, height: 34)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Button(L("Logout"), role: .destructive) { confirmLogout = true }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L("Settings"))
        .alert(L("Confirm logout?"), isPresented: $confirmLogout) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Confirm"), role: .destructive) { store.logout() }
        }
        .sheet(isPresented: $showingProfile) {
            SSOProfileView(url: store.api.profileURL(), token: store.token)
        }
    }
}

struct AppBackground: View {
    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
    }
}

struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func listRowChrome(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct StackText: View {
    var top: String
    var bottom: String
    var alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(top)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(bottom)
                .font(.subheadline.weight(.semibold))
        }
    }
}

struct AvatarView: View {
    var user: UserProfile?
    var member: Member?
    var size: CGFloat = 40

    var displayName: String {
        user?.name ?? member?.name ?? "?"
    }

    var avatarURL: String {
        user?.avatar ?? member?.avatar ?? ""
    }

    var body: some View {
        Group {
            if let url = URL(string: avatarURL), !avatarURL.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(Color(.systemGray5))
            .overlay {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(WalkcalcStore())
}
