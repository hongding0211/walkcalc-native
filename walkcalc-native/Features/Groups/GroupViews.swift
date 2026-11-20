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

struct GroupView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.softLedgerAppTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let groupId: String
    var contentMaxWidth: CGFloat? = nil
    var onClose: (() -> Void)? = nil
    @State private var activeSheet: GroupSheet? = Self.initialSheet()
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var submittedSearchText = ""
    @State private var searchRevision = 0
    @State private var deleteCandidate: WalkRecord?
    @State private var isDeletingRecord = false
    @State private var hasCompletedInitialLoad = false
    @State private var isRefreshingRecords = false
    @State private var recordRefreshID: UUID?
    @State private var scrollTitle = ExpenseScrollTitleState()
    @State private var scrollPosition = ScrollPosition()
    @State private var needsQueryScrollToTop = false
    @State private var displayedFilters: GroupRecordFilters?

    private static func initialSheet() -> GroupSheet? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-open-group-settings") {
            return .groupSettings
        }
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
        #if DEBUG
        if ExpenseScrollTitleVerification.isEnabled { ExpenseScrollTitleVerification.recordReads += 1 }
        #endif
        return store.records(groupId: groupId, search: submittedSearchText)
    }

    private var filters: GroupRecordFilters { store.recordFilters(for: groupId) }

    private var hasLoadedRecords: Bool {
        submittedSearchText.isEmpty
            ? store.recordsByGroup[groupId] != nil
            : store.hasLoadedSearchRecords(groupId: groupId, search: submittedSearchText)
    }

    private struct RecordQuery: Equatable {
        let groupID: String
        let text: String
        let filters: GroupRecordFilters
        let amountBasis: GroupRecordSort.AmountBasis?
        let revision: Int
    }

    private var recordQuery: RecordQuery {
        RecordQuery(groupID: groupId, text: submittedSearchText, filters: filters,
                    amountBasis: store.recordAmountBasis(for: groupId), revision: searchRevision)
    }

    var body: some View {
        #if DEBUG
        let _ = ExpenseScrollTitleVerification.countGroupBody()
        #endif
        ZStack {
            SoftLedgerBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let group {
                        if hasLoadedRecords && records.isEmpty && !filters.hasFilters && submittedSearchText.isEmpty && !isRefreshingRecords {
                            GroupRecordsEmptyState()
                        } else {
                            // The group list already supplies this summary; record
                            // loading must not hide it or replace it with a placeholder.
                            overview(for: group)
                            .id(ExpenseScrollTarget.overview)
                            GroupBalancesSection(group: group) { selectedMember in
                                activeSheet = .balances(selectedMember)
                            }
                            .id(ExpenseScrollTarget.balances)
                            if isRefreshingRecords || (!hasLoadedRecords && !hasCompletedInitialLoad) {
                                GroupRecordsLoadingSection()
                            } else if hasLoadedRecords && records.isEmpty {
                                Text(L("No matching records"))
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(SoftLedgerTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityAddTraits(.isHeader)
                            } else if hasLoadedRecords {
                                GroupExpensesSection(
                                    group: group,
                                    records: records,
                                    sort: filters.sort,
                                    showsPerPersonAmount: store.showsPerPersonAmount,
                                    isLoadingMore: store.isLoadingRecords(groupId: group.id, search: submittedSearchText),
                                    onDelete: { record in
                                        guard store.canMutateRecord(record, in: group) else { return }
                                        deleteCandidate = record
                                    },
                                    onEdit: { record in
                                        isSearchFocused = false
                                        activeSheet = .editExpense(record)
                                    },
                                    scrollTitle: scrollTitle
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
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
            .defaultScrollAnchor(.top, for: .initialOffset)
            .scrollPosition($scrollPosition)
            .scrollDismissesKeyboard(.interactively)
            .modifier(ExpenseScrollTracking(state: scrollTitle))
            .refreshable { await refreshGroupContent(showLoading: false) }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                let triggerY = max(0, geometry.contentSize.height - 160)
                return visibleBottom >= triggerY
            } action: { _, isNearBottom in
                guard recordRefreshID == nil, !isRefreshingRecords, isNearBottom, let group else { return }
                guard store.canLoadMoreRecords(groupId: group.id, search: submittedSearchText), !store.isLoadingRecords(groupId: group.id, search: submittedSearchText) else { return }
                let query = submittedSearchText
                Task { await store.loadMoreRecords(groupId: group.id, search: query) }
            }

        }
        .modifier(ExpenseNavigationTitle(
            groupName: group?.name ?? L("Group"), state: scrollTitle,
            followsDates: filters.sort.field == .occurredAt
        ))
        .navigationBarTitleDisplayMode(horizontalSizeClass == .regular ? .inline : .large)
        .toolbar {
            if #available(iOS 27.1, *) {
                // Keep both menus together in Duo’s vertical toolbar.
                groupActions.axisBehavior(.verticalPreferred)
            } else {
                groupActions
            }

            recordActions
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: L("Search records"))
        .searchFocused($isSearchFocused)
        .searchPresentationToolbarBehavior(horizontalSizeClass == .regular ? .automatic : .avoidHidingContent)
        .onSubmit(of: .search) {
            submittedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            searchRevision += 1
            needsQueryScrollToTop = true
            isRefreshingRecords = true
            isSearchFocused = false
        }
        .onChange(of: searchText) { _, text in
            // The native clear button removes only the keyword condition.
            if text.isEmpty { clearSubmittedSearch() }
        }
        .onChange(of: isSearchPresented) { _, presented in
            if !presented {
                searchText = ""
                clearSubmittedSearch()
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarVisibility(isSearchPresented ? .automatic : .visible, for: .bottomBar)
        .background { RecordToolbarVisibility(isSearching: isSearchPresented).allowsHitTesting(false) }
        .recordDeleteConfirmation(groupId: groupId, record: $deleteCandidate, isDeleting: $isDeletingRecord) { _ in
            if !submittedSearchText.isEmpty { searchRevision += 1 }
        }
        .onChange(of: filters) { _, _ in
            needsQueryScrollToTop = true
        }
        .onChange(of: recordQuery.amountBasis) { _, _ in
            needsQueryScrollToTop = true
        }
        .onChange(of: groupId) { _, _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                activeSheet = nil
                isSearchPresented = false
                isSearchFocused = false
                searchText = ""
                submittedSearchText = ""
                searchRevision = 0
                deleteCandidate = nil
                isDeletingRecord = false
                recordRefreshID = nil
                isRefreshingRecords = false
                hasCompletedInitialLoad = false
                displayedFilters = nil
                needsQueryScrollToTop = false
                scrollTitle.reset()
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .task(id: recordQuery) { await refreshGroupContent() }
        .onChange(of: activeSheet?.id) { previous, current in
            if previous != nil, current == nil, !submittedSearchText.isEmpty,
               !store.hasLoadedSearchRecords(groupId: groupId, search: submittedSearchText) {
                searchRevision += 1
            }
        }
        .onChange(of: records.isEmpty) { _, isEmpty in
            if isEmpty { scrollTitle.reset() }
        }
        .sheet(item: $activeSheet) { sheet in
            GroupSheetView(groupId: groupId, sheet: sheet, activeSheet: $activeSheet) {
                if let onClose { onClose() } else { dismiss() }
            }
        }
        .environment(\.groupSheetContentMaxWidth, contentMaxWidth)
    }

    private func overview(for group: WalkGroup) -> some View {
        GroupWalletOverview(group: group) {
            activeSheet = .balances(nil)
        }
            .id(group.id)
    }

    @ToolbarContentBuilder
    private var recordActions: some ToolbarContent {
        // Move the existing system search item; don't add a second trigger or
        // replace it on activation. Its identity must survive presentation and
        // split-view/toolbar-axis transitions so UIKit keeps the same target.
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(.fixed, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                presentNewExpense()
            } label: {
                Label(L("Add expense"), systemImage: "square.and.pencil")
            }
            .accessibilityLabel(L("Add expense"))
        }
    }

    private var groupActions: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            GroupRecordFilterToolbar(
                groupId: groupId,
                filters: filters,
                currencyCodes: filterCurrencyCodes,
                theme: appTheme,
                onRelatedChange: { value in
                    updateRecordFilters { $0.onlyRelatedToMe = value }
                },
                onCurrencyChange: { codes in
                    updateRecordFilters { $0.currencyCodes = codes }
                },
                onCategoryChange: { ids in
                    updateRecordFilters { $0.categoryIds = ids }
                },
                onSortFieldChange: { field in
                    updateRecordFilters { $0.sort.field = field }
                },
                onSortOrderChange: { order in
                    updateRecordFilters { $0.sort.order = order }
                },
                onReset: {
                    updateRecordFilters { $0 = GroupRecordFilters() }
                }
            )
            Menu {
                Section(L("View options")) {
                    Toggle(isOn: $store.showsPerPersonAmount) {
                        Label(L("Per person"), systemImage: "dollarsign.circle")
                    }
                }
                Button {
                    activeSheet = .groupSettings
                } label: {
                    Label(L("Group settings"), systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.primary)
            }
            .menuOrder(.fixed)
            .accessibilityLabel(L("Group actions"))
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

    private func updateRecordFilters(_ update: (inout GroupRecordFilters) -> Void) {
        var next = store.recordFilters(for: groupId)
        update(&next)
        guard next != filters else { return }
        isRefreshingRecords = true
        store.setRecordFilters(next, for: groupId)
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

    private func clearSubmittedSearch() {
        guard !submittedSearchText.isEmpty else { return }
        submittedSearchText = ""
        needsQueryScrollToTop = true
        isRefreshingRecords = true
    }

    private func refreshGroupContent(showLoading: Bool = true) async {
        let request = recordQuery
        let refreshID = UUID()
        recordRefreshID = refreshID
        isRefreshingRecords = showLoading && (!hasLoadedRecords || needsQueryScrollToTop)
        defer {
            // Cancellation must finish loading, but an older request must not
            // clear the indicator owned by a newer search/filter request.
            if recordRefreshID == refreshID {
                recordRefreshID = nil
                isRefreshingRecords = false
            }
        }
        if !hasLoadedRecords { hasCompletedInitialLoad = false }
        await store.refreshGroupContent(groupId, search: request.text)
        guard !Task.isCancelled, recordRefreshID == refreshID, request == recordQuery else { return }
        hasCompletedInitialLoad = true
        // Pull-to-refresh owns its native inset/offset recovery. Issuing a
        // scrollTo while that control collapses can leave the viewport pulled down.
        // Only an explicit search/filter load should reposition the list.
        guard showLoading else { return }
        let filtersChanged = displayedFilters.map { $0 != request.filters } ?? request.filters.isActive
        displayedFilters = request.filters
        if needsQueryScrollToTop || filtersChanged || !request.text.isEmpty {
            needsQueryScrollToTop = false
            scrollTitle.reset()
            scrollPosition.scrollTo(edge: .top)
        }
    }
}

private struct GroupRecordsLoadingSection: View {
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var verticalPadding = 4
    private let cornerRadius = SoftLedgerCornerRadius.card

    var body: some View {
        LedgerPaginationLoadingView()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .softLedgerSurface(cornerRadius: cornerRadius, borderOpacity: 0.62)
    }
}

private struct GroupBalancesSection: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var rowVerticalPadding = 4
    @ScaledMetric(relativeTo: .subheadline) private var dividerLeadingPadding = 54
    @ScaledMetric(relativeTo: .subheadline) private var detailRowMinHeight = 48
    private let cornerRadius = SoftLedgerCornerRadius.card

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
        personalDebts.isEmpty ? L("Member details") : L("Suggested settlement")
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
                    .softLedgerSurface(cornerRadius: cornerRadius, borderOpacity: 0.62)
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
                                Text(L("View details"))
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
                .softLedgerSurface(cornerRadius: cornerRadius, borderOpacity: 0.62)
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
            .softLedgerSurface(cornerRadius: cornerRadius, borderOpacity: 0.62)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Member details"))
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
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .subheadline) private var amountMinWidth = 76

    let debt: ResolvedDebt
    let currentParticipantID: String?
    let currencyCode: String

    var body: some View {
        HStack(spacing: rowSpacing) {
            SettlementAvatarPair(from: debt.from, to: debt.to)

            SettlementRelationshipTitle(debt: debt, currentParticipantID: currentParticipantID)
                .layoutPriority(1)

            Spacer(minLength: 0)

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
        SettlementCopy.title(debt, participantID: currentParticipantID)
    }

    private var displayAmount: String {
        let amount = CurrencyCatalog.formatted(Money.absolute(debt.amountMinor), currencyCode: currencyCode)
        return isCurrentParticipantPayer ? "-\(amount)" : amount
    }

    private var amountColor: Color {
        isCurrentParticipantPayer ? SoftLedgerTheme.negative : SoftLedgerTheme.positive
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
        if !member.currencyBalances.isEmpty {
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
        displayBalances.filter { !Money.isZero($0.debtMinor) }.map {
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

                if carouselBalances.isEmpty {
                    Text(L("Settled"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        .frame(width: amountWidth, height: amountHeight, alignment: .trailing)
                        .layoutPriority(2)
                } else {
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
    var id: ExpenseScrollTarget { .date(date) }
    let date: Date
    let records: [WalkRecord]
}

struct GroupExpensesSection: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var rowVerticalPadding = 4
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54
    @ScaledMetric(relativeTo: .subheadline) private var dividerLeadingPadding = 54
    private let cornerRadius = SoftLedgerCornerRadius.card

    let group: WalkGroup
    let records: [WalkRecord]
    var sort: GroupRecordSort? = nil
    var showsPerPersonAmount = false
    @State private var sections: [ExpenseDateSection] = []
    let isLoadingMore: Bool
    let onDelete: (WalkRecord) -> Void
    let onEdit: (WalkRecord) -> Void
    var scrollTitle: ExpenseScrollTitleState? = nil

    private var sectionCalendar: Calendar {
        sort == nil ? .autoupdatingCurrent : GroupRecordSort.sectionCalendar
    }

    var body: some View {
        if let sort, sort.field == .amount {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let rows = sort.ordered(records, amountBasis: showsPerPersonAmount ? .perPerson : .total)
                recordCard(rows, showsTimeOnly: false, now: context.date, isLoadingMore: isLoadingMore)
            }
            .onAppear { scrollTitle?.retainDates([]) }
        } else {
            dateSections
        }
    }

    private var dateSections: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(TemporalDisplay.sectionTitle(for: section.date, now: context.date, calendar: sectionCalendar))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SoftLedgerTheme.ink)
                            .accessibilityAddTraits(.isHeader)

                        recordCard(
                            section.records, showsTimeOnly: true, now: context.date,
                            isLoadingMore: section.id == sections.last?.id && isLoadingMore
                        )
                    }
                    .modifier(ExpenseDateTracking(date: section.date, state: scrollTitle))
                }

            }
            .onChange(of: records, initial: true) { _, _ in
                rebuildSections(now: context.date)
            }
            .onChange(of: sort) { _, _ in
                rebuildSections(now: context.date)
            }
            .onChange(of: sectionCalendar.startOfDay(for: context.date)) { _, _ in
                rebuildSections(now: context.date)
            }
        }
    }

    private func recordCard(_ records: [WalkRecord], showsTimeOnly: Bool, now: Date, isLoadingMore: Bool) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(records) { record in
                ExpenseRow(
                    record: record,
                    group: group,
                    showsTimeOnly: showsTimeOnly,
                    now: now,
                    showsPerPersonAmount: showsPerPersonAmount,
                    onDelete: store.canMutateRecord(record, in: group) ? { onDelete(record) } : nil
                ) {
                    onEdit(record)
                }
                if record.id != records.last?.id || isLoadingMore {
                    Divider()
                        .overlay(SoftLedgerTheme.rule.opacity(0.56))
                        .padding(.leading, dividerLeadingPadding + rowHorizontalPadding)
                        .padding(.trailing, rowHorizontalPadding)
                }
            }
            if isLoadingMore {
                LedgerPaginationLoadingView()
                    .padding(.horizontal, rowHorizontalPadding)
            }
        }
        .padding(.vertical, rowVerticalPadding)
        .softLedgerSurface(cornerRadius: cornerRadius, borderOpacity: 0.62)
    }

    private func rebuildSections(now: Date) {
        #if DEBUG
        if ExpenseScrollTitleVerification.isEnabled { ExpenseScrollTitleVerification.sectionRebuilds += 1 }
        #endif
        if let sort {
            sections = sort.sections(for: records, now: now).map { ExpenseDateSection(date: $0.date, records: $0.records) }
        } else {
            let grouped = Dictionary(grouping: records) {
                TemporalDisplay.sectionDate(for: $0.occurredAt.walkDate, now: now)
            }
            sections = grouped.keys.sorted(by: >).map { date in
                ExpenseDateSection(date: date, records: (grouped[date] ?? []).sorted {
                    $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt > $1.occurredAt
                })
            }
        }
        scrollTitle?.retainDates(sections.map(\.date))
    }


}

struct ExpenseRow: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var rowHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var rowVerticalPadding = 6
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
    let now: Date
    let showsPerPersonAmount: Bool
    let onDelete: (() -> Void)?
    let action: () -> Void

    init(record: WalkRecord, group: WalkGroup, showsTimeOnly: Bool, now: Date, showsPerPersonAmount: Bool = false, onDelete: (() -> Void)? = nil, action: @escaping () -> Void) {
        self.record = record
        self.group = group
        self.showsTimeOnly = showsTimeOnly
        self.now = now
        self.showsPerPersonAmount = showsPerPersonAmount
        self.onDelete = onDelete
        self.action = action
    }

    private var category: ExpenseCategory {
        expenseCategory(for: record)
    }

    private func participantSummary(compact: Bool = true, nameLimit: Int? = nil) -> String {
        RecordParticipantSummary.text(
            payerID: record.who,
            recipientIDs: record.forWhom,
            names: Dictionary(group.recordMembers.map { ($0.uuid, $0.name) }, uniquingKeysWith: { first, _ in first }),
            currentParticipantID: store.currentParticipantID(for: group),
            isSettlement: record.isDebtResolve,
            compact: compact,
            nameLimit: nameLimit,
            eligibleParticipantIDs: group.allMembers.map(\.uuid)
        )
    }

    private var compactCreatedAt: String {
        showsTimeOnly
            ? TemporalDisplay.timeString(fromMilliseconds: record.occurredAt)
            : TemporalDisplay.recordListDateString(fromMilliseconds: record.occurredAt, now: now)
    }

    private var fullCreatedAt: String {
        TemporalDisplay.string(fromMilliseconds: record.occurredAt, context: .full, now: now)
    }

    var body: some View {
        let isSplit = showsPerPersonAmount && record.hasSplitAmount
        let amount = record.amountMinor(perPerson: showsPerPersonAmount)
        let amountLabel = CurrencyCatalog.formatted(amount, currencyCode: record.currencyCode ?? group.currencyCode)
        let spokenAmount = isSplit ? String(format: L("%@ per person"), amountLabel) : amountLabel

        Button(action: action) {
            HStack(spacing: rowSpacing) {
                ExpenseCategoryBadge(category: category, size: iconSize, symbolSize: iconFontSize)

                VStack(alignment: .leading, spacing: textSpacing) {
                    Text(recordTitle(record))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    RecordParticipantCaption { participantSummary(nameLimit: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: trailingSpacing) {
                    Text(amountLabel)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(SoftLedgerTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                    Text(compactCreatedAt)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SoftLedgerTheme.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
            }
            .padding(.vertical, rowVerticalPadding)
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
        .accessibilityLabel("\(recordTitle(record)), \(participantSummary(compact: false)), \(spokenAmount), \(fullCreatedAt)")
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
