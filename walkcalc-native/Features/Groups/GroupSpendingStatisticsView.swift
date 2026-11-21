import Charts
import SwiftUI

struct GroupSpendingStatisticsView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @ScaledMetric(relativeTo: .subheadline) private var categoryBarHeight = 36
    @ScaledMetric(relativeTo: .subheadline) private var categoryIconSize = 30
    @ScaledMetric(relativeTo: .subheadline) private var categorySymbolSize = 14
    @ScaledMetric(relativeTo: .subheadline) private var categoryRowMinHeight = 54
    private let categoryRowSpacing: CGFloat = 12
    private let categoryCardPadding: CGFloat = 18
    private let contentMaxWidth: CGFloat = 560
    private var badgeBackground = CategoryBadgeBackground()
    #if DEBUG
    @WalletPaletteSettings private var walletPalette: WalletPalette
    #endif

    let group: WalkGroup
    let participantID: String?

    @AppStorage private var walletPositionData: Data
    @AppStorage private var savedCurrency: String
    @AppStorage private var timelineRange: SpendingTimelineRange
    @State private var statistics: GroupSpendingStatistics?
    @State private var selectedCategoryID: String?
    @State private var recordsSelection: RecordsSelection?
    @State private var loadFailed = false
    @State private var retryCount = 0

    init(group: WalkGroup, participantID: String?) {
        self.group = group
        self.participantID = participantID
        let walletKey = WalletCardPosition.storageKey(groupID: group.id, participantID: participantID)
        _walletPositionData = AppStorage(wrappedValue: Data(), walletKey)
        _savedCurrency = AppStorage(wrappedValue: "", "statistics.currency.\(walletKey)")
        _timelineRange = AppStorage(wrappedValue: .week, "statistics.timelineRange.\(walletKey)")
    }

    private var currentGroup: WalkGroup { store.group(id: group.id) ?? group }

    private var defaultCurrency: String {
        CurrencyCatalog.normalizedCode(currentGroup.currencyCode)
    }

    private var walletCurrencies: [String] {
        GroupWalletData.visibleCurrencyCodes(group: currentGroup, participantID: participantID,
                                             currencyCodes: store.recordFilters(for: group.id).currencyCodes)
    }

    private var walletCurrency: String {
        WalletCardPosition.decode(walletPositionData).frontCardID(in: walletCurrencies) ?? defaultCurrency
    }

    private var selectedCurrency: String {
        filterCurrencyCodes.contains(savedCurrency) ? savedCurrency : walletCurrency
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let statistics {
                    dashboard(statistics)
                } else if loadFailed {
                    ContentUnavailableView {
                        Label(L("Statistics unavailable"), systemImage: "chart.bar.xaxis")
                    } actions: {
                        Button(L("Retry")) {
                            loadFailed = false
                            retryCount += 1
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                        .softLedgerProgressTint()
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .frame(maxWidth: contentMaxWidth)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background { SoftLedgerBackground() }
        .navigationTitle(L("Statistics"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .bottomBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                GroupFilterMenu(isActive: false, summary: selectedCurrency) {
                    Menu {
                        Picker(L("Currency"), selection: Binding(
                            get: { selectedCurrency },
                            set: { savedCurrency = $0 }
                        )) {
                            ForEach(filterCurrencyCodes, id: \.self) { code in
                                Text(GroupCurrencyFilterMenu.title(for: code)).tag(code)
                            }
                        }
                        .pickerStyle(.inline)
                        .menuActionDismissBehavior(.disabled)
                    } label: {
                        Label(L("Currency"), systemImage: "dollarsign.circle")
                        Text(selectedCurrency)
                    }
                }
            }
        }
        .task(id: retryCount) {
            let result = await store.groupSpendingStatistics(for: group)
            guard !Task.isCancelled else { return }
            statistics = result.value
            loadFailed = result.failure != nil
        }
        .onChange(of: selectedCurrency) { _, _ in selectedCategoryID = nil }
        .sheet(item: $recordsSelection) { selection in
            SpendingRecordsSheet(
                group: currentGroup, title: selection.title, filter: selection.filter,
                currencyCode: selection.currencyCode
            ) {
                retryCount += 1
            }
            .environment(\.groupSheetContentMaxWidth, contentMaxWidth)
        }
    }

    @ViewBuilder
    private func dashboard(_ statistics: GroupSpendingStatistics) -> some View {
        let currency = selectedCurrency

        categoryCard(categoryRows(statistics.categories, currency: currency), currency: currency)
        memberCard(memberRows(statistics.members, currency: currency), currency: currency)
        SpendingTimelineCard(group: currentGroup, currencyCode: currency, refreshID: retryCount, range: $timelineRange) { interval, title in
            recordsSelection = RecordsSelection(title: title, currencyCode: currency, filter: .period(interval))
        }
    }

    private func categoryCard(_ rows: [CategoryRow], currency: String) -> some View {
        let total = rows.reduce(Decimal.zero) { $0 + $1.amount }
        let selected = rows.first { $0.id == selectedCategoryID }

        return VStack(spacing: 12) {
            VStack(spacing: 10) {
                categorySummary(selected: selected, total: total, currency: currency)
                if rows.isEmpty {
                    Capsule().fill(SoftLedgerTheme.rule)
                        .frame(height: categoryBarHeight)
                        .accessibilityHidden(true)
                } else {
                    categoryBar(rows, total: total, selectedID: selected?.id)
                }
            }

            if rows.isEmpty {
                Text(L("No personal spending in this currency"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        categoryLegendRow(row, currency: currency, selectedID: selected?.id)
                        if row.id != rows.last?.id {
                            Divider()
                                .overlay(SoftLedgerTheme.rule.opacity(0.56))
                                .padding(.leading, categoryIconSize + categoryRowSpacing)
                        }
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
        }
        .padding(categoryCardPadding)
        .frame(maxWidth: .infinity)
        .background(SoftLedgerTheme.formPaper, in: RoundedRectangle(cornerRadius: 24))
    }

    private func categorySummary(selected: CategoryRow?, total: Decimal, currency: String) -> some View {
        let amount = selected?.amount ?? total
        let number = NSDecimalNumber(decimal: amount)
        let compactAmount = CurrencyCatalog.formatted(number.stringValue, currencyCode: currency)
        let share = selected.map { ratio($0.amount, to: total).formatted(.percent.precision(.fractionLength(0))) }
        let title = selected?.name ?? L("Total")

        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                if let share {
                    Text(share)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .transaction { $0.animation = nil }
            Spacer(minLength: 8)
            AnimatedGroupLabel(text: compactAmount, numericValue: number.doubleValue / 100)
                .font(.headline)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(share.map { "\(title), \($0)" } ?? L("My spending by category"))
        .accessibilityValue(amountText(amount, currency: currency))
    }

    private func categoryBar(_ rows: [CategoryRow], total: Decimal, selectedID: String?) -> some View {
        var cumulativeAmount: Decimal = 0
        let segments = rows.map { row in
            let start = ratio(cumulativeAmount, to: total)
            cumulativeAmount += row.amount
            return CategorySegment(id: row.id, start: start, end: ratio(cumulativeAmount, to: total))
        }

        return Chart(segments) { segment in
            let colors = badgeBackground.colors(for: expenseCategory(for: segment.id))
            RectangleMark(
                xStart: .value(L("Amount"), segment.start),
                xEnd: .value(L("Amount"), segment.end),
                yStart: .value("Bottom", 0.0),
                yEnd: .value("Top", 1.0)
            )
            .cornerRadius(0)
            .foregroundStyle(colors.first.mixed(with: colors.second, amount: 0.5).color)
            .opacity(selectedID == nil || segment.id == selectedID ? 1 : 0.28)
        }
        .chartXScale(domain: 0.0...1.0, range: .plotDimension(padding: 0))
        .chartYScale(domain: 0.0...1.0, range: .plotDimension(padding: 0))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear)
                    .contentShape(.rect)
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let plot = proxy.plotFrame else { return }
                        let frame = geometry[plot]
                        guard frame.contains(tap.location),
                              let share = proxy.value(atX: tap.location.x - frame.minX, as: Double.self),
                              let segment = segments.first(where: { share >= $0.start && share < $0.end }) else { return }
                        toggleSelection(segment.id)
                    })
            }
        }
        .frame(height: categoryBarHeight)
        .clipShape(Capsule())
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }

    private func categoryLegendRow(_ row: CategoryRow, currency: String, selectedID: String?) -> some View {
        let isSelected = selectedID == row.id
        let isDimmed = selectedID != nil && !isSelected
        let textColor: Color = isDimmed ? .secondary : .primary

        return HStack(spacing: 8) {
            Button {
                toggleSelection(row.id)
            } label: {
                HStack(spacing: categoryRowSpacing) {
                    ExpenseCategoryBadge(
                        category: expenseCategory(for: row.id),
                        size: categoryIconSize,
                        symbolSize: categorySymbolSize
                    )
                    ZStack(alignment: .leading) {
                        Text(row.name)
                            .opacity(isSelected ? 0 : 1)
                        Text(row.name)
                            .fontWeight(.semibold)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .foregroundStyle(textColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name)
                    Spacer(minLength: 8)
                    Text(amountText(row.amount, currency: currency))
                        .foregroundStyle(textColor)
                        .layoutPriority(1)
                }
                .font(.subheadline)
                .monospacedDigit()
                .frame(minHeight: categoryRowMinHeight)
                .contentShape(.rect)
            }
            .buttonStyle(StatisticsRowButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                recordsSelection = RecordsSelection(
                    title: row.name, currencyCode: currency,
                    filter: .category(ids: row.categoryIDs, includeUncategorized: row.id == CategoryRow.uncategorizedID)
                )
            } label: {
                SpendingStatisticsChevron()
                    .frame(width: 32, height: categoryRowMinHeight, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: L("Show records for %@"), row.name))
        }
        .padding(.trailing, -categoryCardPadding)
    }

    private func toggleSelection(_ id: String) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedCategoryID = selectedCategoryID == id ? nil : id
        }
    }

    private func memberCard(_ rows: [MemberRow], currency: String) -> some View {
        let highest = rows.first?.amount ?? 0
        #if DEBUG
        let palette = walletPalette.entries.map(\.color)
        #else
        let palette = WalletColorPair.defaults.map(\.first)
        #endif
        let paletteStart = GroupWalletData.paletteStart(groupID: group.id, count: palette.count)
        let memberColors = Dictionary(uniqueKeysWithValues: Set(rows.map(\.id)).sorted().enumerated().map { index, id in
            (id, palette[(paletteStart + index) % palette.count].color)
        })

        return LazyVStack(alignment: .leading, spacing: 16) {
            if highest <= 0 {
                Text(L("No member spending in this currency"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    memberRankingRow(row, currency: currency, highest: highest,
                                     color: memberColors[row.id] ?? palette[paletteStart].color)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SoftLedgerTheme.formPaper, in: RoundedRectangle(cornerRadius: 24))
    }

    private func memberRankingRow(_ row: MemberRow, currency: String, highest: Decimal, color: Color) -> some View {
        let isCurrentUser = row.id == participantID
        let name = isCurrentUser ? L("You") : row.member.name

        return Button {
            recordsSelection = RecordsSelection(
                title: memberBillsTitle(row.member, currentParticipantID: participantID),
                currencyCode: currency,
                filter: .member(id: row.id)
            )
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    SoftLedgerAvatarStack(members: [row.member], visibleCount: 1, size: 22, borderColor: SoftLedgerTheme.formPaper)
                        .accessibilityHidden(true)
                    Text(name)
                        .fontWeight(isCurrentUser ? .semibold : .regular)
                    Spacer(minLength: 8)
                    Text(amountText(row.amount, currency: currency))
                        .monospacedDigit()
                    SpendingStatisticsChevron()
                }
                .font(.subheadline)

                GeometryReader { geometry in
                    let fraction = max(0, CGFloat(ratio(row.amount, to: highest)))
                    Capsule().fill(SoftLedgerTheme.rule)
                        .overlay(alignment: .leading) {
                            Capsule().fill(color)
                                .frame(width: geometry.size.width * fraction)
                        }
                }
                .frame(height: 7)
                .accessibilityHidden(true)
            }
            .foregroundStyle(SoftLedgerTheme.ink)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(StatisticsRowButtonStyle())
    }

    private var filterCurrencyCodes: [String] {
        var codes = Set(walletCurrencies)
        codes.insert(defaultCurrency)
        let members = statistics?.members ?? currentGroup.allMembers
        for member in members {
            codes.formUnion(member.currencyBalances.map(\.currencyCode))
        }
        if let statistics {
            codes.formUnion(statistics.categories.map(\.currencyCode))
        }
        return codes.sorted()
    }

    private func categoryRows(_ totals: [SpendingCategoryTotal], currency: String) -> [CategoryRow] {
        let byCategory = Dictionary(grouping: totals.filter { $0.currencyCode == currency }) { total in
            guard let id = total.categoryId, !id.isEmpty else { return CategoryRow.uncategorizedID }
            return expenseCategory(for: id).id
        }
        return byCategory.compactMap { id, entries in
            let amount = entries.reduce(Decimal.zero) { $0 + Money.decimal($1.expenseMinor) }
            guard amount > 0 else { return nil }
            let categoryIDs = Set(entries.compactMap(\.categoryId).filter { !$0.isEmpty }).sorted()
            return CategoryRow(id: id, amount: amount, categoryIDs: categoryIDs)
        }.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
    }

    private func memberRows(_ members: [Member], currency: String) -> [MemberRow] {
        members.map { member in
            let projection = member.currencyBalances.first { $0.currencyCode == currency }
            let legacyAmount = member.currencyBalances.isEmpty && currency == defaultCurrency ? member.costMinor : "0"
            return MemberRow(member: member, amount: Money.decimal(projection?.costMinor ?? legacyAmount))
        }.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
    }

    private func amountText(_ amount: Decimal, currency: String) -> String {
        CurrencyCatalog.symbol(for: currency) + (amount / 100).formatted(.number.precision(.fractionLength(2)))
    }

    private func ratio(_ amount: Decimal, to total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: amount / total).doubleValue
    }

    private struct CategoryRow: Identifiable {
        static let uncategorizedID = "uncategorized"
        let id: String
        let amount: Decimal
        let categoryIDs: [String]

        var name: String {
            id == Self.uncategorizedID ? L("Uncategorized") : L(expenseCategory(for: id).titleKey)
        }
    }

    private struct CategorySegment: Identifiable {
        let id: String
        let start: Double
        let end: Double
    }

    private struct MemberRow: Identifiable {
        var id: String { member.id }
        let member: Member
        let amount: Decimal
    }

    private struct RecordsSelection: Identifiable {
        let id = UUID()
        let title: String
        let currencyCode: String
        let filter: SpendingRecordsFilter
    }
}

struct SpendingStatisticsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SoftLedgerTheme.mutedInk.opacity(0.7))
            .accessibilityHidden(true)
    }
}

private struct StatisticsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
