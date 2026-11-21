import Charts
import SwiftUI
import UIKit

struct SpendingTimelineCard: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    let group: WalkGroup
    let currencyCode: String
    let refreshID: Int
    @Binding var range: SpendingTimelineRange
    let onShowRecords: (DateInterval, String) -> Void

    @State private var load: (request: BoundsRequest, result: LedgerOperationResult<SpendingTimelineSnapshot>)?
    @State private var retry = 0

    private var localCalendar: Calendar {
        var result = calendar
        result.timeZone = timeZone
        return result
    }

    var body: some View {
        let calendar = localCalendar
        let modifiedAt = group.modifiedAt.isFinite && group.modifiedAt > 0 ? group.modifiedAt : nil
        let key = SpendingTimelineCacheKey(
            scope: .init(participantID: store.currentParticipantID(for: group), groupID: group.id,
                         currencyCode: currencyCode, calendarID: String(describing: calendar.identifier),
                         timeZoneID: calendar.timeZone.identifier),
            modifiedAt: modifiedAt
        )
        let request = BoundsRequest(key: key, refreshID: modifiedAt == nil ? refreshID : 0, retry: retry)

        VStack(alignment: .leading, spacing: 14) {
            Picker(L("Time range"), selection: $range) {
                ForEach(SpendingTimelineRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            switch load?.request == request ? load?.result : nil {
            case .success(let snapshot):
                SpendingTimelineViewport(
                    group: group, currencyCode: currencyCode, snapshot: snapshot, cacheKey: key,
                    range: range, calendar: calendar, onShowRecords: onShowRecords
                )
                .id(request)
            case .failure:
                ContentUnavailableView {
                    Label(L("Statistics unavailable"), systemImage: "chart.bar.xaxis")
                } actions: {
                    Button(L("Retry")) { retry += 1 }
                        .buttonStyle(.bordered)
                }
            case nil:
                ProgressView()
                    .softLedgerProgressTint()
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SoftLedgerTheme.formPaper, in: RoundedRectangle(cornerRadius: 24))
        .task(id: request) {
            if load?.request == request, case .success = load?.result { return }
            let diskCache = SpendingTimelineDiskCache.shared
            if let snapshot = await diskCache.load(for: key) {
                guard !Task.isCancelled else { return }
                load = (request, .success(snapshot))
                return
            }
            guard !Task.isCancelled else { return }
            let result = await store.spendingTimelineBounds(for: group, currencyCode: currencyCode)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let bounds):
                let snapshot = SpendingTimelineSnapshot(modifiedAt: key.modifiedAt, bounds: bounds)
                await diskCache.storeBounds(snapshot, for: key)
                guard !Task.isCancelled else { return }
                load = (request, .success(snapshot))
            case .failure(let failure):
                load = (request, .failure(failure))
            }
        }
    }

    private struct BoundsRequest: Hashable {
        let key: SpendingTimelineCacheKey
        let refreshID: Int
        let retry: Int
    }
}

enum SpendingTimelineRange: String, CaseIterable, Hashable {
    case week, month, year

    var title: String {
        switch self {
        case .week: L("Week")
        case .month: L("Month")
        case .year: L("Year")
        }
    }

    var bucket: Calendar.Component { self == .year ? .month : .day }

    var windowSize: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 12
        }
    }

    var tickStride: Int {
        switch self {
        case .week: 1
        case .month: 7
        case .year: 3
        }
    }
}

private struct SpendingTimelineViewport: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.locale) private var locale
    private var badgeBackground = CategoryBadgeBackground()

    let group: WalkGroup
    let currencyCode: String
    let bounds: ClosedRange<Date>?
    let cacheKey: SpendingTimelineCacheKey
    let range: SpendingTimelineRange
    let calendar: Calendar
    let onShowRecords: (DateInterval, String) -> Void

    @State private var positions: [SpendingTimelineRange: Double] = [:]
    @State private var settledStarts: [SpendingTimelineRange: Int] = [:]
    @State private var cache: TimelineCache
    @State private var isScrolling = false
    @State private var pending: DateInterval?
    @State private var failed: DateInterval?
    @State private var loader: Task<Void, Never>?

    init(group: WalkGroup, currencyCode: String, snapshot: SpendingTimelineSnapshot, cacheKey: SpendingTimelineCacheKey,
         range: SpendingTimelineRange, calendar: Calendar, onShowRecords: @escaping (DateInterval, String) -> Void) {
        self.group = group
        self.currencyCode = currencyCode
        self.bounds = snapshot.bounds
        self.cacheKey = cacheKey
        self.range = range
        self.calendar = calendar
        self.onShowRecords = onShowRecords
        _cache = State(initialValue: snapshot.cache)
    }

    var body: some View {
        let scale = TimelineScale(range: range, bounds: bounds, calendar: calendar)
        let position = Binding(
            get: { positions[range] ?? Double(scale.latestStart) },
            set: { positions[range] = $0 }
        )
        let first = scale.startIndex(at: position.wrappedValue)
        let interval = scale.window(startingAt: first)
        let title = windowLabel(interval)
        let total = cache.points(in: interval).reduce("0") { Money.add($0, $1.expenseMinor) }

        VStack(alignment: .leading, spacing: 10) {
            Button {
                onShowRecords(interval, title)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CurrencyCatalog.formatted(total, currencyCode: currencyCode))
                            .font(.headline)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityLabel(CurrencyCatalog.formatted(total, currencyCode: currencyCode, style: .exact))
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    SpendingStatisticsChevron()
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(format: L("Show records for %@"), title))
            .accessibilityIdentifier("spendingTimelineRecords")

            chart(scale: scale, position: position, first: first)
                .id(range)
                .accessibilityIdentifier("spendingTimelineChart")
                .overlay {
                    if let failed, failed.start < interval.end, interval.start < failed.end {
                        Button(L("Retry")) {
                            self.failed = nil
                            scheduleLoad(for: interval)
                        }
                        .buttonStyle(.bordered)
                    }
                }
        }
        .onChange(of: range, initial: true) {
            isScrolling = false
            scheduleLoad(for: interval)
        }
        .onDisappear {
            pending = nil
            loader?.cancel()
        }
    }

    private func chart(scale: TimelineScale, position: Binding<Double>, first: Int) -> some View {
        let windowSize = range.windowSize
        let settled = settledStarts[range] ?? scale.latestStart
        let buffer = max(0, min(first, settled) - windowSize)..<min(scale.plotEnd, max(first, settled) + windowSize * 2)
        let plotted = DateInterval(start: scale.date(at: buffer.lowerBound), end: scale.date(at: buffer.upperBound))
        let segments = segmentsByBucket(cache.points(in: plotted), scale: scale)
        let categories = Array(Set(segments.map(\.category))).sorted { $0.name < $1.name }
        let visible = settled..<(settled + windowSize)
        let visiblePeak = segments.lazy.filter { visible.contains($0.bucket) }.map(\.end).max() ?? 0
        let top = max(1, visiblePeak * 1.1)
        let axisBuckets = isScrolling ? buffer : first..<(first + windowSize)
        let ticks = axisBuckets.filter { $0.isMultiple(of: range.tickStride) }.map { Double($0) + 0.5 }

        return Chart(segments) { segment in
            // A taller bar can scroll in before the vertical scale adjusts at rest.
            if segment.start < top {
                RectangleMark(
                    xStart: .value(L("Date"), Double(segment.bucket) + 0.14),
                    xEnd: .value(L("Date"), Double(segment.bucket) + 0.86),
                    yStart: .value(L("Amount"), segment.start),
                    yEnd: .value(L("Amount"), min(segment.end, top))
                )
                .foregroundStyle(by: .value(L("Category"), segment.category.name))
                .accessibilityLabel("\(axisLabel(scale.date(at: segment.bucket), detailed: true)), \(segment.category.name)")
                .accessibilityValue(CurrencyCatalog.formatted(segment.amount, currencyCode: currencyCode, style: .exact))
            }
        }
        .chartForegroundStyleScale(domain: categories.map(\.name), range: categories.map { category in
            let colors = badgeBackground.colors(for: expenseCategory(for: category.id))
            return colors.first.mixed(with: colors.second, amount: 0.5).color
        })
        .chartXScale(domain: 0...Double(scale.plotEnd), range: .plotDimension(padding: 0))
        .chartYScale(domain: 0...top)
        .chartPlotStyle { plot in
            plot.background {
                SpendingTimelinePanPriority()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: Double(windowSize))
        .chartScrollPosition(x: position)
        .chartScrollTargetBehavior(.valueAligned(unit: 1))
        .onScrollPhaseChange { _, phase in
            isScrolling = phase != .idle
            if phase == .idle {
                let start = scale.startIndex(at: position.wrappedValue)
                settledStarts[range] = start
                scheduleLoad(for: scale.window(startingAt: start))
            } else {
                pending = nil
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: ticks) { value in
                if let x = value.as(Double.self) {
                    AxisValueLabel(
                        LocalizedStringKey(axisLabel(scale.date(at: Int(x)), detailed: false)),
                        centered: false,
                        anchor: .top,
                        collisionResolution: .disabled,
                        orientation: .horizontal
                    )
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                if visiblePeak > 0 || value.as(Double.self) == 0 {
                    AxisValueLabel()
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
    }

    private func scheduleLoad(for interval: DateInterval) {
        guard let bounds, let latestDay = calendar.dateInterval(of: .day, for: bounds.upperBound) else { return }
        let earliestDay = calendar.startOfDay(for: bounds.lowerBound)
        let start = max(earliestDay, interval.start)
        let end = min(latestDay.end, interval.end)
        guard start < end else { return }
        let visible = DateInterval(start: start, end: end)
        guard !cache.missing(in: visible).isEmpty,
              failed.map({ $0.start < end && start < $0.end }) != true else {
            pending = nil
            return
        }

        let earlier = calendar.date(byAdding: .day, value: -8, to: start) ?? start
        pending = DateInterval(start: max(earliestDay, earlier), end: end)
        startLoader()
    }

    private func startLoader() {
        guard loader == nil, pending != nil, !isScrolling else { return }
        loader = Task {
            defer {
                loader = nil
                startLoader()
            }
            while let requested = pending, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                guard pending == requested else { continue }
                pending = nil
                for gap in cache.missing(in: requested).reversed() {
                    let result = await store.spendingTimeline(
                        for: group, currencyCode: currencyCode, interval: gap, bucket: .day, calendar: calendar
                    )
                    guard !Task.isCancelled else { return }
                    switch result {
                    case .success(let points):
                        cache.store(points, for: gap)
                        await SpendingTimelineDiskCache.shared.store(points, in: gap, bounds: bounds, for: cacheKey)
                        guard !Task.isCancelled else { return }
                    case .failure:
                        failed = gap
                        pending = nil
                        return
                    }
                    // A newer window takes precedence over the remaining prefetch gaps.
                    if isScrolling || pending != nil { break }
                }
            }
        }
    }

    private func segmentsByBucket(_ points: [SpendingTimelinePoint], scale: TimelineScale) -> [Segment] {
        Dictionary(grouping: points) { scale.index(for: $0.date) }.flatMap { index, points -> [Segment] in
            let grouped = Dictionary(grouping: points) { point in
                Category(id: point.categoryID.map { expenseCategory(for: $0).id } ?? "uncategorized")
            }
            var runningTotal = Decimal.zero
            return grouped.keys.sorted { $0.id < $1.id }.map { category in
                let amount = grouped[category, default: []].reduce("0") { Money.add($0, $1.expenseMinor) }
                let start = NSDecimalNumber(decimal: runningTotal / 100).doubleValue
                runningTotal += Money.decimal(amount)
                return Segment(bucket: index, category: category, amount: amount, start: start,
                               end: NSDecimalNumber(decimal: runningTotal / 100).doubleValue)
            }
        }
    }

    private func windowLabel(_ interval: DateInterval) -> String {
        let start = interval.start
        let end = calendar.date(byAdding: range.bucket, value: -1, to: interval.end) ?? start
        var style = Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
        if range != .year { style = style.day() }
        if !calendar.isDate(start, equalTo: .now, toGranularity: .year)
            || !calendar.isDate(end, equalTo: .now, toGranularity: .year) {
            style = style.year()
        }
        return style.format(start..<end)
    }

    private func axisLabel(_ date: Date, detailed: Bool) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if range == .year { return date.formatted(style.month(.abbreviated)) }
        return date.formatted(detailed ? style.month(.abbreviated).day() : style.day())
    }

    private struct Category: Hashable {
        let id: String

        var name: String {
            id == "uncategorized" ? L("Uncategorized") : L(expenseCategory(for: id).titleKey)
        }
    }

    private struct Segment: Identifiable {
        var id: String { "\(bucket)/\(category.id)" }
        let bucket: Int
        let category: Category
        let amount: MoneyMinor
        let start: Double
        let end: Double
    }
}

private struct TimelineScale {
    let range: SpendingTimelineRange
    let calendar: Calendar
    let origin: Date
    let latestStart: Int

    var plotEnd: Int { latestStart + range.windowSize }

    init(range: SpendingTimelineRange, bounds: ClosedRange<Date>?, calendar: Calendar) {
        self.range = range
        self.calendar = calendar
        let newest = bounds?.upperBound ?? .now
        let oldest = bounds?.lowerBound ?? newest
        let first = calendar.dateInterval(of: range.bucket, for: oldest)?.start ?? oldest
        let last = calendar.dateInterval(of: range.bucket, for: newest)?.start ?? newest
        origin = first
        let latestIndex = calendar.dateComponents([range.bucket], from: first, to: last).value(for: range.bucket) ?? 0
        latestStart = max(0, latestIndex + 1 - range.windowSize / 2)
    }

    func startIndex(at position: Double) -> Int {
        min(latestStart, max(0, Int(position.rounded())))
    }

    func index(for date: Date) -> Int {
        let bucket = calendar.dateInterval(of: range.bucket, for: date)?.start ?? date
        return calendar.dateComponents([range.bucket], from: origin, to: bucket).value(for: range.bucket) ?? 0
    }

    func date(at index: Int) -> Date {
        calendar.date(byAdding: range.bucket, value: index, to: origin) ?? origin
    }

    func window(startingAt index: Int) -> DateInterval {
        DateInterval(start: date(at: index), end: date(at: index + range.windowSize))
    }
}

private struct SpendingTimelinePanPriority: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var registeredPan: UIPanGestureRecognizer?

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            prioritizeScrollPan()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            prioritizeScrollPan()
        }

        private func prioritizeScrollPan() {
            guard let navigationController else { return }
            var ancestor = view.superview
            while let current = ancestor, !(current is UIScrollView) {
                ancestor = current.superview
            }
            guard let pan = (ancestor as? UIScrollView)?.panGestureRecognizer, pan !== registeredPan else { return }
            navigationController.interactiveContentPopGestureRecognizer?.require(toFail: pan)
            navigationController.interactivePopGestureRecognizer?.require(toFail: pan)
            registeredPan = pan
        }
    }
}
