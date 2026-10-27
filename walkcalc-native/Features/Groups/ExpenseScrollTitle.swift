import SwiftUI

enum ExpenseScrollTarget: Hashable {
    case overview
    case balances
    case date(Date)
}

/// Only small tracking/title modifiers observe this state. GroupView passes
/// the reference without reading the changing date or involving the store.
@Observable
final class ExpenseScrollTitleState {
    let coordinateSpace = UUID()
    var topInset: CGFloat = 0
    private(set) var date: Date?
    private(set) var layoutRevision = 0
    @ObservationIgnored private var activeDates: Set<Date> = []
    @ObservationIgnored private var validDates: Set<Date> = []
    @ObservationIgnored private var updatePending = false

    func retainDates(_ dates: [Date]) {
        let next = Set(dates)
        if validDates != next {
            validDates = next
            layoutRevision += 1
        }
        activeDates.formIntersection(validDates)
        if let date, !validDates.contains(date) {
            self.date = nil
        }
        scheduleUpdate()
    }

    func setActive(_ isActive: Bool, for date: Date, revision: Int) {
        guard revision == layoutRevision, validDates.contains(date) else { return }
        if isActive { activeDates.insert(date) }
        else { activeDates.remove(date) }
        scheduleUpdate()
    }

    func reset() {
        activeDates.removeAll()
        validDates.removeAll()
        layoutRevision += 1
        date = nil
    }

    private func scheduleUpdate() {
        guard !updatePending else { return }
        updatePending = true
        // Adjacent sections can enter/leave in either callback order. Publish
        // their combined result after layout, without a transient group title.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePending = false
            let next = self.activeDates.min()
            if self.date != next { self.date = next }
        }
    }
}

struct ExpenseScrollTracking: ViewModifier {
    let state: ExpenseScrollTitleState

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: state.coordinateSpace)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentInsets.top
            } action: { _, inset in
                state.topInset = inset
            }
            #if DEBUG
            .onAppear {
                if ExpenseScrollTitleVerification.isEnabled {
                    ExpenseScrollTitleVerification.state = state
                }
            }
            #endif
    }
}

struct ExpenseDateTracking: ViewModifier {
    let date: Date
    let state: ExpenseScrollTitleState?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let state {
            let top = state.topInset
            let revision = state.layoutRevision
            content
                .onGeometryChange(for: ExpenseDateVisibility.self) { proxy in
                    let frame = proxy.frame(in: .named(state.coordinateSpace))
                    // The 16pt inter-section gap belongs to the preceding date.
                    return ExpenseDateVisibility(revision: revision, isActive: frame.minY <= top && frame.maxY + 16 > top)
                } action: { visibility in
                    state.setActive(visibility.isActive, for: date, revision: visibility.revision)
                }
                .onDisappear { state.setActive(false, for: date, revision: revision) }
        } else {
            content
        }
    }
}

/// A new data layout must re-report even when its Boolean matches the old one.
nonisolated private struct ExpenseDateVisibility: Equatable, Sendable {
    let revision: Int
    let isActive: Bool
}

struct ExpenseNavigationTitle: ViewModifier {
    let groupName: String
    let state: ExpenseScrollTitleState
    @State private var now = Date()

    func body(content: Content) -> some View {
        content
            .navigationTitle(title(now: now))
            // Keep the navigation preference on the original content. Only
            // invalidate this modifier when the calendar day actually changes.
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                    let next = Date()
                    if !Calendar.autoupdatingCurrent.isDate(now, inSameDayAs: next) {
                        now = next
                    }
                }
            }
    }

    private func title(now: Date) -> String {
        if let date = state.date {
            return TemporalDisplay.sectionTitle(for: date, now: now)
        }
        return groupName
    }
}
