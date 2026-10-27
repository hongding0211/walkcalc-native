#if DEBUG
import SwiftUI

/// Opt-in integration checks against the real group view and native scroll
/// title and date-boundary tracking. No backend writes or simulated touch events.
@MainActor
enum ExpenseScrollTitleVerification {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("--verify-expense-scroll-title")
    static weak var state: ExpenseScrollTitleState?
    static var groupBodies = 0
    static var recordReads = 0
    static var sectionRebuilds = 0

    static func countGroupBody() {
        if isEnabled { groupBodies += 1 }
    }

    static func run(proxy: ScrollViewProxy, store: WalkcalcStore, presentSheet: (Bool) -> Void) async {
        do {
            try await Task.sleep(for: .seconds(2))
            check("tracking registered", state != nil)
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: Date())
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let older = TemporalDisplay.sectionDate(for: calendar.date(byAdding: .day, value: -2, to: today)!, now: today)
            check("overview", state?.date == nil)
            check("native group title", navigationTitle() == "Scroll verification")

            try await scroll(proxy, to: ExpenseScrollTarget.date(today), anchor: .top)
            check("today at top", state?.date == today)
            check("native date title", navigationTitle() == TemporalDisplay.sectionTitle(for: today))
            let reads = recordReads
            let bodies = groupBodies
            let rebuilds = sectionRebuilds

            // Today's 60 records are much taller than the viewport. Aligning
            // its bottom hides its heading while the top still shows today.
            try await scroll(proxy, to: ExpenseScrollTarget.date(today), anchor: .bottom)
            check("long section keeps date", state?.date == today)
            check("same-section record reads", recordReads == reads)
            check("same-section group body", groupBodies == bodies)
            check("same-section regrouping", sectionRebuilds == rebuilds)

            try await scroll(proxy, to: ExpenseScrollTarget.date(older), anchor: .top)
            check("forward date", state?.date == older)
            try await scroll(proxy, to: ExpenseScrollTarget.date(yesterday), anchor: .top)
            check("reverse date", state?.date == yesterday)
            check("cross-section record reads", recordReads == reads)
            check("cross-section group body", groupBodies == bodies)

            presentSheet(true)
            try await Task.sleep(for: .seconds(1))
            presentSheet(false)
            try await Task.sleep(for: .seconds(1))
            check("sheet return retains date", state?.date == yesterday)

            var appended = store.recordsByGroup["stress-0"]!.last!
            appended.recordId = "scroll-verification-appended"
            appended.occurredAt = calendar.date(byAdding: .day, value: -40, to: today)!.timeIntervalSince1970 * 1000
            store.recordsByGroup["stress-0", default: []].append(appended)
            try await Task.sleep(for: .seconds(1))
            check("append retains section", state?.date == yesterday)

            store.recordsByGroup["stress-0"]?.removeAll {
                TemporalDisplay.sectionDate(for: $0.occurredAt.walkDate) == yesterday
            }
            try await Task.sleep(for: .seconds(1))
            check("deleted date is cleared", state?.date != yesterday)

            try await scroll(proxy, to: ExpenseScrollTarget.overview, anchor: .top)
            check("return to overview", state?.date == nil)
            check("native group title restored", navigationTitle() == "Scroll verification")
            try await scroll(proxy, to: ExpenseScrollTarget.date(today), anchor: .top)
            store.setRecordFilters(GroupRecordFilters(currencyCodes: ["USD"]), for: "stress-0")
            try await Task.sleep(for: .seconds(1))
            check("empty filter clears date", state?.date == nil)
            store.setRecordFilters(GroupRecordFilters(), for: "stress-0")
            try await Task.sleep(for: .seconds(1))
            try await scroll(proxy, to: ExpenseScrollTarget.date(today), anchor: .top)
            check("filter reset restores tracking", state?.date == today)
            store.recordsByGroup["stress-0"] = []
            try await Task.sleep(for: .seconds(1))
            check("empty content", state?.date == nil)
            print("EXPENSE_SCROLL_TITLE_VERIFICATION: \(failures == 0 ? "PASSED" : "FAILED (\(failures))")")
        } catch {
            print("EXPENSE_SCROLL_TITLE_VERIFICATION: CANCELLED")
        }
    }

    private static func scroll(_ proxy: ScrollViewProxy, to target: ExpenseScrollTarget, anchor: UnitPoint) async throws {
        // Lazy stacks refine estimated heights after realizing a distant target.
        // Align again after that layout before asserting its viewport identity.
        for _ in 0..<2 {
            proxy.scrollTo(target, anchor: anchor)
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    private static var failures = 0
    private static func navigationTitle() -> String? {
        func title(in view: UIView) -> String? {
            if let nav = view as? UINavigationBar { return nav.topItem?.title }
            return view.subviews.lazy.compactMap { title(in: $0) }.first
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            if let title = scene.windows.lazy.compactMap({ title(in: $0) }).first { return title }
        }
        return nil
    }
    private static func check(_ name: String, _ passed: Bool) {
        if !passed { failures += 1 }
        print("SCROLL_TITLE_CHECK \(name): \(passed ? "PASS" : "FAIL") target=\(String(describing: state?.date)) bodies=\(groupBodies) reads=\(recordReads) groups=\(sectionRebuilds)")
    }
}

struct ExpenseScrollTitleVerificationHost: View {
    @StateObject private var store = makeStore()
    @State private var isSheetPresented = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                GroupView(groupId: "stress-0")
                    .environmentObject(store)
                    .task {
                        await ExpenseScrollTitleVerification.run(proxy: proxy, store: store) { isSheetPresented = $0 }
                    }
            }
        }
        .sheet(isPresented: $isSheetPresented) {
            Text("Scroll title verification")
                .presentationDetents([.medium])
        }
    }

    private static func makeStore() -> WalkcalcStore {
        let store = WalkcalcStore()
        store.applyDebugFixture(.scroll)
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        store.recordsByGroup["stress-0"] = store.recordsByGroup["stress-0"]!.enumerated().map { index, record in
            var record = record
            let dayOffset = index < 60 ? 0 : 1 + (index - 60) / 6
            record.occurredAt = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
                .addingTimeInterval(Double(180 - index)).timeIntervalSince1970 * 1000
            return record
        }
        return store
    }
}

#endif
