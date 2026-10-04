import SwiftUI
import UIKit

enum GroupSheet: Identifiable {
    case newExpense
    case editExpense(WalkRecord)
    case groupSettings
    case balances(Member?)
    case myBalance(Member)
    case peopleSetup

    var id: String {
        switch self {
        case .newExpense: "newExpense"
        case .editExpense(let record): "editExpense-\(record.recordId)"
        case .groupSettings: "groupSettings"
        case .balances(let member): "balances-\(member?.id ?? "root")"
        case .myBalance(let member): "myBalance-\(member.id)"
        case .peopleSetup: "peopleSetup"
        }
    }
}

private extension GroupSheet {
    var keepsTopBalanceVisible: Bool {
        switch self {
        case .balances, .myBalance:
            return true
        case .newExpense, .editExpense, .groupSettings, .peopleSetup:
            return false
        }
    }
}

struct GroupView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.softLedgerAppTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    let groupId: String
    @State private var activeSheet: GroupSheet? = Self.initialSheet()
    @State private var isSearchPresented = false
    @State private var isSystemSearchPresented = false
    @State private var ignoredSearchText = ""
    @State private var deleteCandidate: WalkRecord?
    @State private var isDeletingRecord = false
    @State private var hasCompletedInitialLoad = false
    @State private var isRefreshingRecords = false

    private static func initialSheet() -> GroupSheet? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-open-new-expense") {
            return .newExpense
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-open-balances") {
            return .balances(nil)
        }
        #endif
        return nil
    }

    private var group: WalkGroup? {
        store.group(id: groupId)
    }

    private var records: [WalkRecord] {
        store.records(groupId: groupId)
    }

    private var filters: GroupRecordFilters { store.recordFilters(for: groupId) }

    private var hasLoadedRecords: Bool {
        store.recordsByGroup[groupId] != nil
    }

    private var filterIconColor: Color {
        guard filters.isActive else { return .primary }
        switch appTheme {
        case .mono: return Color(uiColor: .systemBackground)
        case .yellow, .green: return .black
        case .blue, .pink: return .white
        }
    }

    private var isBalanceAnimationEnabled: Bool {
        (activeSheet == nil || activeSheet?.keepsTopBalanceVisible == true)
            && !isSearchPresented
            && !isSystemSearchPresented
            && deleteCandidate == nil
            && !isDeletingRecord
    }

    var body: some View {
        ZStack {
            SoftLedgerBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let group {
                        if hasLoadedRecords && records.isEmpty && !filters.isActive {
                            GroupRecordsEmptyState()
                        } else {
                            // The group list already supplies this summary; record
                            // loading must not hide it or replace it with a placeholder.
                            GroupSummaryCard(group: group, isAnimationEnabled: isBalanceAnimationEnabled) { member in
                                activeSheet = .myBalance(member)
                            }
                            GroupBalancesSection(group: group) { selectedMember in
                                activeSheet = .balances(selectedMember)
                            }
                            if isRefreshingRecords || (!hasLoadedRecords && !hasCompletedInitialLoad) {
                                GroupRecordsLoadingSection()
                            } else if hasLoadedRecords {
                                GroupExpensesSection(
                                    group: group,
                                    records: records,
                                    isLoadingMore: store.isLoadingRecords(groupId: group.id),
                                    onDelete: { record in
                                        guard store.canMutateRecord(record, in: group) else { return }
                                        deleteCandidate = record
                                    },
                                    onEdit: { record in
                                        activeSheet = .editExpense(record)
                                    }
                                )
                            } else if hasCompletedInitialLoad {
                                recordLoadFailure
                            }
                        }
                    } else if hasCompletedInitialLoad {
                        recordLoadFailure
                    } else {
                        ProgressView()
                            .softLedgerProgressTint()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
            .refreshable { await refreshGroupContent() }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                let triggerY = max(0, geometry.contentSize.height - 160)
                return visibleBottom >= triggerY
            } action: { _, isNearBottom in
                guard isNearBottom, let group else { return }
                guard store.canLoadMoreRecords(groupId: group.id), !store.isLoadingRecords(groupId: group.id) else { return }
                Task { await store.loadMoreRecords(groupId: group.id) }
            }
        }
        .navigationTitle(group?.name ?? L("Group"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    GroupRecordFilterMenu(
                        filters: Binding(
                            get: { filters },
                            set: { next in
                                guard next != filters else { return }
                                isRefreshingRecords = true
                                store.setRecordFilters(next, for: groupId)
                            }
                        ),
                        currencyCodes: filterCurrencyCodes
                    )
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(filterIconColor)
                        .background {
                            Circle()
                                .fill(filters.isActive ? appTheme.accent : .clear)
                                .frame(width: 32, height: 32)
                        }
                }
                .accessibilityLabel(L("Filters"))
                .accessibilityValue(filters.summary)
                .menuActionDismissBehavior(.disabled)
                Button {
                    activeSheet = .groupSettings
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(L("Group settings"))
            }

            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    presentNewExpense()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(L("Add expense"))
            }
        }
        .searchable(text: $ignoredSearchText, isPresented: $isSystemSearchPresented, placement: .toolbar, prompt: L("Search records"))
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onChange(of: isSystemSearchPresented) { _, isPresented in
            guard isPresented else { return }
            ignoredSearchText = ""
            isSystemSearchPresented = false
            isSearchPresented = true
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .recordDeleteConfirmation(groupId: groupId, record: $deleteCandidate, isDeleting: $isDeletingRecord)
        .task(id: filters) { await refreshGroupContent() }
        .sheet(isPresented: $isSearchPresented) {
            if let group {
                NavigationStack {
                    RecordSearchCanvas(group: group)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            GroupSheetView(groupId: groupId, sheet: sheet, activeSheet: $activeSheet) {
                dismiss()
            }
        }
    }

    // Derive options from the whole ledger's projections, never the filtered page.
    private var filterCurrencyCodes: [String] {
        var codes = filters.currencyCodes
        if let group {
            codes.insert(CurrencyCatalog.normalizedCode(group.currencyCode))
            codes.formUnion(group.currentUserCurrencyBalances.map(\.currencyCode))
            for member in group.allMembers {
                codes.formUnion(member.currencyBalances.map(\.currencyCode))
            }
        }
        return codes.sorted()
    }

    private func presentNewExpense() {
        activeSheet = .newExpense
    }

    private var recordLoadFailure: some View {
        VStack(spacing: 18) {
            Text(L("Couldn't load records"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(L("Retry")) {
                Task { await refreshGroupContent() }
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func refreshGroupContent() async {
        if !hasLoadedRecords {
            hasCompletedInitialLoad = false
            isRefreshingRecords = true
        }
        await store.refreshGroupContent(groupId)
        guard !Task.isCancelled else { return }
        isRefreshingRecords = false
        hasCompletedInitialLoad = true
    }
}

private struct GroupRecordsLoadingSection: View {
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var verticalPadding = 4
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius = 16

    var body: some View {
        LedgerPaginationLoadingView()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
            }
    }
}

private struct GroupRecordFilterMenu: View {
    @Binding var filters: GroupRecordFilters
    let currencyCodes: [String]

    private var currencySubtitle: String {
        let codes = filters.currencyCodes.sorted()
        guard !codes.isEmpty else { return L("All currencies") }
        let visible = codes.prefix(2).joined(separator: ", ")
        return codes.count > 2 ? "\(visible), … +\(codes.count - 2)" : visible
    }

    var body: some View {
        Button {
            filters.onlyRelatedToMe.toggle()
        } label: {
            Label {
                Text(L("Related to me"))
            } icon: {
                Image(uiImage: filters.onlyRelatedToMe ? FilterMenuImages.personSelected : FilterMenuImages.person)
            }
        }
        .accessibilityAddTraits(filters.onlyRelatedToMe ? .isSelected : [])
        .menuActionDismissBehavior(.disabled)

        Menu {
            ForEach(currencyCodes, id: \.self) { code in
                let selected = filters.currencyCodes.contains(code)
                Button {
                    if selected { filters.currencyCodes.remove(code) }
                    else { filters.currencyCodes.insert(code) }
                } label: {
                    Label {
                        Text("\(code) · \(CurrencyCatalog.currencyInfo(for: code).name)")
                    } icon: {
                        Image(uiImage: selected ? FilterMenuImages.checked : FilterMenuImages.unchecked)
                    }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            Label {
                Text(L("Currency"))
            } icon: {
                Image(uiImage: FilterMenuImages.currency)
            }
            Text(currencySubtitle)
        }
        .menuActionDismissBehavior(.disabled)
    }
}

private enum FilterMenuImages {
    // System menus insert their state column only once a Toggle is selected.
    // Keep that space in the image bounds instead, leaving native row layout
    // and submenu presentation intact in both states.
    static let person = indicator(symbol: "person.crop.circle", selected: false)
    static let personSelected = indicator(symbol: "person.crop.circle", selected: true)
    static let currency = indicator(symbol: "dollarsign.circle", selected: false)
    static let checked = indicator(selected: true)
    static let unchecked = indicator(selected: false)

    private static func indicator(symbol: String? = nil, selected: Bool) -> UIImage {
        // Include trailing breathing room as well: UIKit centers a custom menu
        // image in its image column rather than laying out a SwiftUI HStack.
        let size = CGSize(width: symbol == nil ? 16 : 40, height: 20)
        return UIGraphicsImageRenderer(size: size).image { _ in
            if selected, let check = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)) {
                check.draw(at: CGPoint(x: 0, y: (size.height - check.size.height) / 2))
            }
            if let symbol, let icon = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)) {
                icon.draw(at: CGPoint(x: 16 + (18 - icon.size.width) / 2, y: (size.height - icon.size.height) / 2))
            }
        }.withRenderingMode(.alwaysTemplate)
    }
}

private struct RecordSearchCanvas: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .subheadline) private var dividerLeadingPadding = 54
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""
    @State private var selectedRecord: WalkRecord?
    @State private var deleteCandidate: WalkRecord?
    @State private var isPreparingSearch = false
    @State private var hasFocusedSearch = false

    let group: WalkGroup

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var records: [WalkRecord] {
        guard !trimmedQuery.isEmpty else { return [] }
        return store.records(groupId: group.id, search: trimmedQuery)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty && (isPreparingSearch || store.isLoadingRecords(groupId: group.id, search: trimmedQuery))
    }

    private var hasLoadedSearch: Bool {
        store.hasLoadedSearchRecords(groupId: group.id, search: trimmedQuery)
    }

    private var canLoadMoreSearch: Bool {
        store.canLoadMoreRecords(groupId: group.id, search: trimmedQuery)
    }

    var body: some View {
        ZStack {
            SoftLedgerBackground()

            VStack(alignment: .leading, spacing: 14) {
                searchField
                if !trimmedQuery.isEmpty {
                    resultList
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(L("Search records"))
        .navigationBarTitleDisplayMode(.inline)
        .softLedgerDismissesKeyboardOnBackgroundTap(isActive: isSearchFocused) {
            isSearchFocused = false
        }
        .navigationDestination(item: $selectedRecord) { record in
            RecordEditorView(groupId: group.id, record: record) {}
        }
        .recordDeleteConfirmation(groupId: group.id, record: $deleteCandidate) { deletedRecord in
            if selectedRecord?.recordId == deletedRecord.recordId {
                selectedRecord = nil
            }
        }
        .task {
            guard !hasFocusedSearch else { return }
            hasFocusedSearch = true
            isSearchFocused = true
        }
        .task(id: trimmedQuery) {
            let query = trimmedQuery
            // Returning from a record must keep the loaded pages and scroll position.
            guard !query.isEmpty, !hasLoadedSearch else {
                isPreparingSearch = false
                return
            }
            isPreparingSearch = true
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await store.searchRecordsIfNeeded(groupId: group.id, query: query)
            isPreparingSearch = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.secondaryInk)

            TextField(L("Search notes and categories"), text: $query)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .softLedgerAccentTint()
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SoftLedgerTheme.mutedInk)
                }
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SoftLedgerTheme.rule.opacity(0.68), lineWidth: 1)
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if records.isEmpty && isSearching {
                    searchingRow
                        .padding(.horizontal, rowHorizontalPadding)
                } else if records.isEmpty && !isSearching && hasLoadedSearch {
                    Text(L("No matching records"))
                        .font(.subheadline)
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(.horizontal, rowHorizontalPadding)
                } else {
                    ForEach(records) { record in
                        ExpenseRow(
                            record: record,
                            group: group,
                            onDelete: store.canMutateRecord(record, in: group) ? {
                                deleteCandidate = record
                            } : nil
                        ) {
                            isSearchFocused = false
                            selectedRecord = record
                        }

                        if record.id != records.last?.id {
                            Divider()
                                .overlay(SoftLedgerTheme.rule.opacity(0.56))
                                .padding(.leading, dividerLeadingPadding + rowHorizontalPadding)
                                .padding(.trailing, rowHorizontalPadding)
                        }
                    }

                    if isSearching {
                        if !records.isEmpty {
                            Divider()
                                .overlay(SoftLedgerTheme.rule.opacity(0.56))
                                .padding(.leading, dividerLeadingPadding + rowHorizontalPadding)
                                .padding(.trailing, rowHorizontalPadding)
                        }
                        searchingRow
                            .padding(.horizontal, rowHorizontalPadding)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
            let triggerY = max(0, geometry.contentSize.height - 160)
            return visibleBottom >= triggerY
        } action: { _, isNearBottom in
            guard isNearBottom, !trimmedQuery.isEmpty else { return }
            guard canLoadMoreSearch, !store.isLoadingRecords(groupId: group.id, search: trimmedQuery) else { return }
            Task { await store.loadMoreRecords(groupId: group.id, search: trimmedQuery) }
        }
    }

    private var searchingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .softLedgerProgressTint()
            Text(L("Searching records..."))
                .font(.subheadline)
                .foregroundStyle(SoftLedgerTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

private struct GroupSummaryCard: View {
    @EnvironmentObject private var store: WalkcalcStore
    let group: WalkGroup
    let isAnimationEnabled: Bool
    let onOpenBalance: (Member) -> Void

    private var currentMember: Member? {
        guard let userId = store.currentParticipantID(for: group) else { return nil }
        return group.allMembers.first { $0.uuid == userId }
    }

    private var balances: [CurrencyBalanceSummary] {
        store.filteredCurrencyBalances(allBalances, groupId: group.id)
    }

    private var allBalances: [CurrencyBalanceSummary] {
        let projections = group.hasCurrentUserBalanceSummary
            ? group.currentUserCurrencyBalances
            : currentMember?.currencyBalances ?? []
        let actualBalances = projections
            .filter(\.hasLedgerActivity)
            .sorted { $0.currencyCode < $1.currencyCode }
        if !actualBalances.isEmpty {
            return actualBalances.map {
                CurrencyBalanceSummary(currencyCode: $0.currencyCode, totalBalanceMinor: $0.debtMinor)
            }
        }
        let legacyBalance = group.hasCurrentUserBalanceSummary
            ? group.currentUserBalanceMinor
            : currentMember?.debtMinor ?? "0"
        let legacyRecordCount = group.hasCurrentUserBalanceSummary
            ? group.currentUserRecordCount
            : currentMember?.recordCount ?? 0
        guard legacyRecordCount > 0 || !Money.isZero(legacyBalance) else { return [] }
        return [CurrencyBalanceSummary(
            currencyCode: CurrencyCatalog.normalizedCode(group.currencyCode),
            totalBalanceMinor: legacyBalance
        )]
    }

    private func balanceStateText(_ balance: CurrencyBalanceSummary) -> String {
        switch Money.compare(balance.totalBalanceMinor, "0") {
        case .orderedDescending:
            return L("Owed to you")
        case .orderedAscending:
            return L("You owe")
        case .orderedSame:
            return L("Settled")
        }
    }

    var body: some View {
        SoftLedgerCard {
            if balances.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Total balance"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    Text("0")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(SoftLedgerTheme.ink)
                }
            } else {
                CurrencyBalanceCarousel(
                    balances: balances,
                    isAnimationEnabled: isAnimationEnabled,
                    subtitle: balanceStateText
                ) { _ in
                    guard let currentMember else { return }
                    onOpenBalance(currentMember)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(currentMember != nil)
    }
}

private struct GroupBalancesSection: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var rowVerticalPadding = 4
    @ScaledMetric(relativeTo: .subheadline) private var dividerLeadingPadding = 54
    @ScaledMetric(relativeTo: .subheadline) private var detailRowMinHeight = 48
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius = 16

    let group: WalkGroup
    let onSelect: (Member?) -> Void

    private var balances: [Member] {
        let filters = store.recordFilters(for: group.id)
        let members = store.balancesInServerOrder(for: group)
        guard !filters.currencyCodes.isEmpty else { return members }
        return members.filter { member in
            if !member.currencyBalances.isEmpty {
                return member.currencyBalances.contains {
                    filters.includesCurrency($0.currencyCode) && $0.hasLedgerActivity
                }
            }
            return filters.includesCurrency(group.currencyCode)
                && (member.recordCount > 0 || !Money.isZero(member.debtMinor) || !Money.isZero(member.costMinor))
        }
    }

    private var visibleBalances: [Member] {
        Array(balances.prefix(3))
    }

    private var personalDebts: [ResolvedDebt] {
        store.personalResolvedDebts(for: group)
    }

    private var sectionTitle: String {
        personalDebts.isEmpty ? L("Balances") : L("Suggested settlement")
    }

    private var footerTitle: String {
        if !personalDebts.isEmpty {
            return L("View details")
        }
        return balances.count > 3 ? L("View all") : L("View details")
    }

    private var isSuggestionReady: Bool {
        !group.hasUnresolvedBalance || store.isSettlementSuggestionReady(for: group.id)
    }

    @ViewBuilder
    var body: some View {
        if isSuggestionReady {
            if !personalDebts.isEmpty || !balances.isEmpty {
                balancesContent
            }
        } else {
            loadingContent
        }
    }

    private var balancesContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(sectionTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)
                .padding(.top, 4)

            if !personalDebts.isEmpty {
                Button {
                    onSelect(nil)
                } label: {
                    VStack(spacing: 0) {
                        ForEach(Array(personalDebts.enumerated()), id: \.element.id) { index, debt in
                            PersonalSettlementPreviewRow(
                                debt: debt,
                                currentParticipantID: store.currentParticipantID(for: group),
                                currencyCode: debt.currencyCode
                            )
                            if index < personalDebts.count - 1 {
                                Divider()
                                    .overlay(SoftLedgerTheme.rule.opacity(0.54))
                                    .padding(.leading, dividerLeadingPadding)
                            }
                        }

                        Divider()
                            .overlay(SoftLedgerTheme.rule.opacity(0.54))
                            .padding(.leading, dividerLeadingPadding)

                        HStack(spacing: 8) {
                            Text(L("View details"))
                                .font(.subheadline.weight(.semibold))
                                .softLedgerAccentForeground()
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
                        }
                        .frame(minHeight: detailRowMinHeight)
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .padding(.vertical, rowVerticalPadding)
                    .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    if !visibleBalances.isEmpty {
                        ForEach(visibleBalances) { member in
                            BalancePreviewRow(member: member, recordCount: recordCount(for: member), currencyCode: group.currencyCode, currencyCodes: store.recordFilters(for: group.id).currencyCodes) {
                                onSelect(member)
                            }
                            if member.id != visibleBalances.last?.id {
                                Divider()
                                    .overlay(SoftLedgerTheme.rule.opacity(0.54))
                                    .padding(.leading, dividerLeadingPadding)
                            }
                        }
                    }

                    if !visibleBalances.isEmpty {
                        Divider()
                            .overlay(SoftLedgerTheme.rule.opacity(0.54))
                            .padding(.leading, dividerLeadingPadding)

                        Button {
                            onSelect(nil)
                        } label: {
                            HStack(spacing: 8) {
                                Text(footerTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .softLedgerAccentForeground()
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
                            }
                            .frame(minHeight: detailRowMinHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, rowVerticalPadding)
                .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                }
            }
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(SoftLedgerTheme.rule.opacity(0.45))
                .frame(width: 142, height: 18)
                .padding(.top, 4)

            HStack {
                ProgressView()
                    .controlSize(.small)
                    .softLedgerProgressTint()
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Balances"))
    }

    private func recordCount(for member: Member) -> Int {
        if member.recordCount > 0 {
            return member.recordCount
        }
        return (store.recordsByGroup[group.id] ?? []).filter { record in
            record.who == member.uuid || record.forWhom.contains(member.uuid)
        }.count
    }
}

private struct PersonalSettlementPreviewRow: View {
    @Environment(\.softLedgerAppTheme) private var appTheme

    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 30
    @ScaledMetric(relativeTo: .caption) private var receiverAvatarSize = 20
    @ScaledMetric(relativeTo: .caption) private var arrowBadgeSize = 18
    @ScaledMetric(relativeTo: .caption2) private var arrowBadgeFontSize = 9
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .caption) private var textSpacing = 4
    @ScaledMetric(relativeTo: .caption) private var receiverSpacing = 6
    @ScaledMetric(relativeTo: .subheadline) private var amountMinWidth = 76

    let debt: ResolvedDebt
    let currentParticipantID: String?
    let currencyCode: String

    var body: some View {
        HStack(spacing: rowSpacing) {
            payerAvatar

            VStack(alignment: .leading, spacing: textSpacing) {
                Text(relationshipTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                HStack(spacing: receiverSpacing) {
                    SoftLedgerAvatar(member: debt.to, size: receiverAvatarSize)
                        .accessibilityHidden(true)

                    Text(L("Settle with %@").replacingOccurrences(of: "%@", with: counterpartyName))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: rowSpacing)

            Text(displayAmount)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .frame(minWidth: amountMinWidth, alignment: .trailing)
                .layoutPriority(3)
        }
        .frame(minHeight: rowMinHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(relationshipTitle), \(displayAmount)")
    }

    private var isCurrentParticipantPayer: Bool {
        debt.from.uuid == currentParticipantID
    }

    private var relationshipTitle: String {
        if isCurrentParticipantPayer {
            return L("You owe %@").replacingOccurrences(of: "%@", with: debt.to.name)
        }
        if debt.to.uuid == currentParticipantID {
            return L("%@ owes you").replacingOccurrences(of: "%@", with: debt.from.name)
        }
        return "\(debt.from.name) \(L("pays")) \(debt.to.name)"
    }

    private var counterpartyName: String {
        isCurrentParticipantPayer ? debt.to.name : debt.from.name
    }

    private var displayAmount: String {
        let amount = CurrencyCatalog.formatted(Money.absolute(debt.amountMinor), currencyCode: currencyCode)
        return isCurrentParticipantPayer ? "-\(amount)" : amount
    }

    private var amountColor: Color {
        isCurrentParticipantPayer ? SoftLedgerTheme.negative : SoftLedgerTheme.positive
    }

    private var payerAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            SoftLedgerAvatar(member: debt.from, size: avatarSize)
                .accessibilityHidden(true)

            Image(systemName: "arrow.right")
                .font(.system(size: arrowBadgeFontSize, weight: .bold))
                .foregroundStyle(SoftLedgerTheme.paper)
                .frame(width: arrowBadgeSize, height: arrowBadgeSize)
                .background(appTheme.accent, in: Circle())
                .overlay {
                    Circle()
                        .stroke(SoftLedgerTheme.paper, lineWidth: max(1, arrowBadgeSize / 9))
                }
                .offset(x: 2, y: 2)
                .accessibilityHidden(true)
        }
        .frame(width: avatarSize + 3, height: avatarSize + 3)
    }
}

struct BalancePreviewRow: View {
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 30
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .caption) private var textSpacing = 4
    @ScaledMetric(relativeTo: .subheadline) private var amountWidth = 82
    @ScaledMetric(relativeTo: .subheadline) private var amountHeight = 24

    let member: Member
    let recordCount: Int
    let currencyCode: String
    var currencyCodes: Set<String> = []
    let action: () -> Void

    private var displayBalances: [MemberCurrencyProjection] {
        allDisplayBalances.filter { currencyCodes.isEmpty || currencyCodes.contains($0.currencyCode) }
    }

    private var allDisplayBalances: [MemberCurrencyProjection] {
        let actualBalances = member.currencyBalances
            .filter(\.hasLedgerActivity)
            .sorted { $0.currencyCode < $1.currencyCode }
        if !actualBalances.isEmpty {
            return actualBalances
        }
        guard recordCount > 0 || !Money.isZero(member.debtMinor) || !Money.isZero(member.costMinor) else {
            return []
        }
        return [MemberCurrencyProjection(
                currencyCode: CurrencyCatalog.normalizedCode(currencyCode),
                debtMinor: member.debtMinor,
                costMinor: member.costMinor,
                paidTotalMinor: "0",
                recordCount: member.recordCount,
                settlementInMinor: "0",
                settlementOutMinor: "0"
            )]
    }

    private var carouselBalances: [CurrencyBalanceSummary] {
        displayBalances.map {
            CurrencyBalanceSummary(
                currencyCode: $0.currencyCode,
                totalBalanceMinor: $0.debtMinor
            )
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: rowSpacing) {
                SoftLedgerAvatar(member: member, size: avatarSize)

                VStack(alignment: .leading, spacing: textSpacing) {
                    Text(member.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(L("%@ records").replacingOccurrences(of: "%@", with: "\(currencyCodes.isEmpty ? recordCount : displayBalances.reduce(0) { $0 + $1.recordCount })"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                }
                .layoutPriority(1)

                Spacer()

                if !carouselBalances.isEmpty {
                    CurrencyBalanceCarousel(
                        compactBalances: carouselBalances,
                        isAnimationEnabled: true,
                        amountColor: { moneyColor($0.totalBalanceMinor) }
                    )
                    .frame(width: amountWidth, height: amountHeight, alignment: .trailing)
                    .layoutPriority(2)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct ExpenseDateSection: Identifiable {
    var id: Date { date }
    let date: Date
    let records: [WalkRecord]
}

struct GroupExpensesSection: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var rowVerticalPadding = 4
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var dividerLeadingPadding = 54
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius = 16

    let group: WalkGroup
    let records: [WalkRecord]
    @State private var sections: [ExpenseDateSection] = []
    let isLoadingMore: Bool
    let onDelete: (WalkRecord) -> Void
    let onEdit: (WalkRecord) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(TemporalDisplay.sectionTitle(for: section.date, now: context.date))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.ink)
                            .accessibilityAddTraits(.isHeader)

                        LazyVStack(spacing: 0) {
                            ForEach(section.records) { record in
                                ExpenseRow(
                                    record: record,
                                    group: group,
                                    showsTimeOnly: true,
                                    onDelete: store.canMutateRecord(record, in: group) ? {
                                        onDelete(record)
                                    } : nil
                                ) {
                                    onEdit(record)
                                }
                                if record.id != section.records.last?.id {
                                    Divider()
                                        .overlay(SoftLedgerTheme.rule.opacity(0.56))
                                        .padding(.leading, dividerLeadingPadding + rowHorizontalPadding)
                                        .padding(.trailing, rowHorizontalPadding)
                                }
                            }
                            if section.id == sections.last?.id && isLoadingMore {
                                Divider()
                                    .overlay(SoftLedgerTheme.rule.opacity(0.56))
                                    .padding(.leading, dividerLeadingPadding + rowHorizontalPadding)
                                    .padding(.trailing, rowHorizontalPadding)
                                LedgerPaginationLoadingView()
                                    .padding(.horizontal, rowHorizontalPadding)
                            }
                        }
                        .padding(.vertical, rowVerticalPadding)
                        .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
                        }
                    }
                }

            }
            .onChange(of: records, initial: true) { _, _ in
                rebuildSections(now: context.date)
            }
            .onChange(of: Calendar.autoupdatingCurrent.startOfDay(for: context.date)) { _, _ in
                rebuildSections(now: context.date)
            }
        }
    }

    private func rebuildSections(now: Date) {
        let grouped = Dictionary(grouping: records) {
            TemporalDisplay.sectionDate(for: $0.occurredAt.walkDate, now: now)
        }
        sections = grouped.keys.sorted(by: >).map { date in
            ExpenseDateSection(date: date, records: (grouped[date] ?? []).sorted {
                $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt > $1.occurredAt
            })
        }
    }


}

struct ExpenseRow: View {
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .subheadline) private var trailingColumnWidth = 106
    @ScaledMetric(relativeTo: .subheadline) private var iconSize = 30
    @ScaledMetric(relativeTo: .subheadline) private var iconFontSize = 14
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .subheadline) private var previewCornerRadius = 12
    @ScaledMetric(relativeTo: .caption) private var textSpacing = 4
    @ScaledMetric(relativeTo: .caption2) private var trailingSpacing = 4

    let record: WalkRecord
    let group: WalkGroup
    let showsTimeOnly: Bool
    let onDelete: (() -> Void)?
    let action: () -> Void

    init(record: WalkRecord, group: WalkGroup, showsTimeOnly: Bool = false, onDelete: (() -> Void)? = nil, action: @escaping () -> Void) {
        self.record = record
        self.group = group
        self.showsTimeOnly = showsTimeOnly
        self.onDelete = onDelete
        self.action = action
    }

    private var payer: Member? {
        group.recordMembers.first(where: { $0.uuid == record.who })
    }

    private var category: ExpenseCategory {
        expenseCategory(for: record)
    }

    private var payerName: String {
        payer?.name ?? L("Unknown")
    }

    private var payerHandleText: String {
        "@\(payerName)"
    }

    private var compactCreatedAt: String {
        showsTimeOnly
            ? TemporalDisplay.timeString(fromMilliseconds: record.occurredAt)
            : TemporalDisplay.string(fromMilliseconds: record.occurredAt, context: .dense)
    }

    private var fullCreatedAt: String {
        TemporalDisplay.string(fromMilliseconds: record.occurredAt, context: .full)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: rowSpacing) {
                Image(systemName: category.symbol)
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .foregroundStyle(category.color)
                    .frame(width: iconSize, height: iconSize)
                    .background(category.color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: textSpacing) {
                    Text(recordTitle(record))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(payerHandleText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                }
                .layoutPriority(1)

                Spacer()

                VStack(alignment: .trailing, spacing: trailingSpacing) {
                    Text(CurrencyCatalog.formatted(record.paidMinor, currencyCode: record.currencyCode ?? group.currencyCode))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(compactCreatedAt)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: trailingColumnWidth, alignment: .trailing)
                .layoutPriority(2)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
            }
            .frame(minHeight: rowMinHeight)
            .padding(.horizontal, rowHorizontalPadding)
            .background(
                SoftLedgerTheme.paper,
                in: RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
        )
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(L("Delete"), systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(recordTitle(record)), \(L("Paid by %@").replacingOccurrences(of: "%@", with: payerName)), \(CurrencyCatalog.formatted(record.paidMinor, currencyCode: record.currencyCode ?? group.currencyCode)), \(fullCreatedAt)")
    }
}

struct RecordDeleteConfirmationModifier: ViewModifier {
    @EnvironmentObject private var store: WalkcalcStore

    let groupId: String
    @Binding var record: WalkRecord?
    let externalIsDeleting: Binding<Bool>?
    let onDeleted: (WalkRecord) -> Void
    @State private var localIsDeleting = false

    private var isDeleting: Bool {
        externalIsDeleting?.wrappedValue ?? localIsDeleting
    }

    func body(content: Content) -> some View {
        content
            .disabled(isDeleting)
            .overlay {
                if isDeleting {
                    ProgressView()
                        .softLedgerProgressTint()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .alert(
                L("Confirm delete?"),
                isPresented: Binding(
                    get: { record != nil && !isDeleting },
                    set: { isPresented in
                        if !isPresented, !isDeleting {
                            record = nil
                        }
                    }
                )
            ) {
                Button(L("Cancel"), role: .cancel) {
                    record = nil
                }
                Button(L("Delete"), role: .destructive) {
                    guard let candidate = record else { return }
                    Task {
                        await delete(candidate)
                    }
                }
            }
    }

    private func delete(_ candidate: WalkRecord) async {
        guard !isDeleting else { return }
        setDeleting(true)
        let result = await store.deleteRecordWithFeedback(groupId: groupId, recordId: candidate.recordId)
        if result.success {
            SoftLedgerHaptics.success()
            onDeleted(candidate)
        }
        record = nil
        setDeleting(false)
    }

    private func setDeleting(_ value: Bool) {
        if let externalIsDeleting {
            externalIsDeleting.wrappedValue = value
        } else {
            localIsDeleting = value
        }
    }
}
extension View {
    func recordDeleteConfirmation(
        groupId: String,
        record: Binding<WalkRecord?>,
        isDeleting: Binding<Bool>? = nil,
        onDeleted: @escaping (WalkRecord) -> Void = { _ in }
    ) -> some View {
        modifier(RecordDeleteConfirmationModifier(groupId: groupId, record: record, externalIsDeleting: isDeleting, onDeleted: onDeleted))
    }
}

private struct GroupRecordsEmptyState: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(SoftLedgerTheme.paper, in: Circle())
                .overlay {
                    Circle().stroke(SoftLedgerTheme.rule.opacity(0.65), lineWidth: 1)
                }

            VStack(spacing: 8) {
                Text(L("No records yet"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.ink)

                Text(L("Add your first expense."))
                    .font(.subheadline)
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}
