import Charts
import SwiftUI

struct GroupSpendingStatisticsView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.softLedgerAppTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var ringSize = 174.0

    let group: WalkGroup
    let participantID: String?

    @AppStorage private var walletPositionData: Data
    @AppStorage private var savedCurrency: String
    @State private var statistics: GroupSpendingStatistics?
    @State private var selectedCategoryID: String?
    @State private var loadFailed = false
    @State private var retryCount = 0

    init(group: WalkGroup, participantID: String?) {
        self.group = group
        self.participantID = participantID
        let walletKey = WalletCardPosition.storageKey(groupID: group.id, participantID: participantID)
        _walletPositionData = AppStorage(wrappedValue: Data(), walletKey)
        _savedCurrency = AppStorage(wrappedValue: "", "statistics.currency.\(walletKey)")
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
            .frame(maxWidth: 560)
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
    }

    @ViewBuilder
    private func dashboard(_ statistics: GroupSpendingStatistics) -> some View {
        let currency = selectedCurrency

        categoryCard(categoryRows(statistics.categories, currency: currency), currency: currency)
        memberCard(memberRows(statistics.members, currency: currency), currency: currency)
    }

    private func categoryCard(_ rows: [CategoryRow], currency: String) -> some View {
        let total = rows.reduce(Decimal.zero) { $0 + $1.amount }
        let visibleSectorCount = rows.count > 7 ? 6 : 7
        let featured = Array(rows.prefix(visibleSectorCount))
        let remainder = rows.dropFirst(visibleSectorCount).reduce(Decimal.zero) { $0 + $1.amount }
        let sectors = remainder > 0 ? featured + [CategoryRow(id: CategoryRow.remainderID, amount: remainder)] : featured
        let selected = selectedCategoryID.flatMap { id in
            rows.first { $0.id == id } ?? sectors.first { $0.id == id }
        }
        let selectedSectorID = selected.map { row in
            sectors.contains { $0.id == row.id } ? row.id : CategoryRow.remainderID
        }
        let diameter = min(ringSize, 250)

        return VStack(spacing: 20) {
            ZStack {
                if rows.isEmpty {
                    Circle().strokeBorder(SoftLedgerTheme.rule, lineWidth: diameter * 0.13)
                        .accessibilityHidden(true)
                } else {
                    Chart {
                        ForEach(sectors) { row in
                            SectorMark(angle: .value(L("Amount"), ratio(row.amount, to: total)),
                                       innerRadius: .ratio(0.73), angularInset: sectors.count > 1 ? 1 : 0)
                                .foregroundStyle(row.color)
                                .opacity(selectedSectorID == nil || row.id == selectedSectorID ? 1 : 0.28)
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear)
                                .contentShape(.rect)
                                .gesture(SpatialTapGesture().onEnded { tap in
                                    let frame = proxy.plotFrame.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
                                    let distance = hypot(tap.location.x - frame.midX, tap.location.y - frame.midY)
                                    let radius = min(frame.width, frame.height) / 2
                                    if distance < radius * 0.73 {
                                        selectedCategoryID = nil
                                    } else if distance <= radius {
                                        let position = CGPoint(x: tap.location.x - frame.minX, y: tap.location.y - frame.minY)
                                        let angle = proxy.angle(at: position).degrees
                                        let fraction = (angle + 360).truncatingRemainder(dividingBy: 360) / 360
                                        if let sector = sector(at: fraction, in: sectors, total: total) {
                                            toggleSelection(sector.id)
                                        }
                                    }
                                })
                        }
                    }
                    .accessibilityHidden(true)
                }

                VStack(spacing: 3) {
                    if let selected {
                        Text(selected.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(amountText(selected?.amount ?? total, currency: currency))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, diameter * 0.18)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(selected?.name ?? L("My spending by category"))
                .accessibilityValue(amountText(selected?.amount ?? total, currency: currency))
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity)

            if rows.isEmpty {
                Text(L("No personal spending in this currency"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let isSelected = selected?.id == row.id
                        Button {
                            toggleSelection(row.id)
                        } label: {
                            HStack(spacing: 9) {
                                Circle().fill(index < visibleSectorCount ? row.color : Color.secondary)
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(row.name)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                Spacer(minLength: 8)
                                Text(ratio(row.amount, to: total).formatted(.percent.precision(.fractionLength(0))))
                                    .foregroundStyle(.secondary)
                                Text(amountText(row.amount, currency: currency))
                            }
                            .font(.subheadline)
                            .monospacedDigit()
                            .frame(minHeight: 34)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(SoftLedgerTheme.formPaper, in: RoundedRectangle(cornerRadius: 24))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedCategoryID)
    }

    private func sector(at value: Double, in sectors: [CategoryRow], total: Decimal) -> CategoryRow? {
        var upperBound = 0.0
        for sector in sectors {
            upperBound += ratio(sector.amount, to: total)
            if value < upperBound { return sector }
        }
        return sectors.last
    }

    private func toggleSelection(_ id: String) {
        selectedCategoryID = selectedCategoryID == id ? nil : id
    }

    private func memberCard(_ rows: [MemberRow], currency: String) -> some View {
        let highest = rows.first?.amount ?? 0

        return LazyVStack(alignment: .leading, spacing: 16) {
            if highest <= 0 {
                Text(L("No member spending in this currency"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    let isCurrentUser = row.member.id == participantID
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            SoftLedgerAvatarStack(members: [row.member], visibleCount: 1, size: 22, borderColor: SoftLedgerTheme.formPaper)
                                .accessibilityHidden(true)
                            Text(isCurrentUser ? L("Me") : row.member.name)
                                .fontWeight(isCurrentUser ? .semibold : .regular)
                            Spacer(minLength: 8)
                            Text(amountText(row.amount, currency: currency))
                                .monospacedDigit()
                        }
                        .font(.subheadline)

                        Chart {
                            BarMark(
                                x: .value(L("Amount"), ratio(row.amount, to: highest)),
                                y: .value(L("Members"), row.id),
                                height: .fixed(7)
                            )
                                .cornerRadius(4)
                                .foregroundStyle(isCurrentUser ? theme.accent : theme.accent.opacity(0.38))
                        }
                        .chartXScale(domain: 0.0...1.0, range: .plotDimension(padding: 0))
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 7)
                        .background(SoftLedgerTheme.rule, in: Capsule())
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SoftLedgerTheme.formPaper, in: RoundedRectangle(cornerRadius: 24))
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
        var byCategory: [String: Decimal] = [:]
        for total in totals where total.currencyCode == currency {
            let category = total.categoryId.map { expenseCategory(for: $0).id } ?? "uncategorized"
            byCategory[category, default: .zero] += Money.decimal(total.expenseMinor)
        }
        return byCategory.compactMap { id, amount in
            amount > 0 ? CategoryRow(id: id, amount: amount) : nil
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
        static let remainderID = "remainingCategories"
        let id: String
        let amount: Decimal

        var name: String {
            switch id {
            case Self.remainderID: L("Remaining categories")
            case "uncategorized": L("Uncategorized")
            default: L(expenseCategory(for: id).titleKey)
            }
        }

        var color: Color {
            if id == "uncategorized" || id == Self.remainderID { return .secondary }
            let rgb = expenseCategory(for: id).paletteColor
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }

    private struct MemberRow: Identifiable {
        var id: String { member.id }
        let member: Member
        let amount: Decimal
    }
}
