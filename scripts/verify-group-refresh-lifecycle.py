#!/usr/bin/env python3
"""Exercise real refresh methods with controlled out-of-order/cancelled responses."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
store = (root / 'walkcalc-native/App/WalkcalcStore.swift').read_text()
view = (root / 'walkcalc-native/Features/Groups/GroupViews.swift').read_text()
def method(source, signature):
    start = source.index(signature)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func', 1)
methods = '\n'.join(method(store, name) for name in [
    '    func preloadGroupContent(', '    func refreshGroupContent(', '    func refreshGroup(',
    '    private func waitForPendingGroupPins(', '    private func resumeGroupPinWaiters('
])
view_method = method(view, '    private func refreshGroupContent(')
harness = r'''
import Foundation
struct GroupRecordFilters: Equatable { var category = 0; var isActive: Bool { category != 0 } }
struct Query: Equatable { var text = ""; var filters = GroupRecordFilters() }
struct WalkGroup { var pinnedAt: Double? }
struct Snapshot { var group: WalkGroup?; var refreshedToken: String?; var source = 0; var records = [1]; var recordPagination: Pagination? }
struct Pagination { var total: Int }
enum Failure: Error { case failed }
enum Intent { case backgroundRefresh }
enum Disposition { case silent }
@MainActor final class Repository {
    var requests: [CheckedContinuation<Result<Snapshot, Failure>, Never>?] = []
    var filters: [GroupRecordFilters] = []
    func groupDetail(groupId: String, recordPageSize: Int, recordSearch: GroupRecordFilters, context: Int) async -> Result<Snapshot, Failure> {
        filters.append(recordSearch)
        return await withCheckedContinuation { requests.append($0) }
    }
    func finish(_ index: Int, pin: Double? = nil, fail: Bool = false) {
        let request = requests[index]!
        requests[index] = nil
        request.resume(returning: fail ? .failure(.failed) : .success(Snapshot(group: WalkGroup(pinnedAt: pin))))
    }
}
@MainActor final class Store {
    struct GroupContentQuery: Equatable { var text: String; var filters: GroupRecordFilters }
    var groupContentRefreshTasks: [String: Task<Void, Never>] = [:]
    var groupContentRefreshQueries: [String: GroupContentQuery] = [:]
    var groupContentRefreshIDs: [String: UUID] = [:]
    var groupPinWaiters: [CheckedContinuation<Void, Never>] = []
    var pendingGroupPins: [String: UUID] = [:]
    var groupListRevision = 0
    var currentGroup = WalkGroup()
    var currentFilters = GroupRecordFilters()
    var isFixtureMode = false
    struct API { var ledgerAPIEnabled = true }
    let api = API()
    let ledgerRepository = Repository()
    let recordPageSize = 10
    var recordsByGroup: [String: [Int]] = [:]
    var recordTotals: [String: Int] = [:]
    var recordSearchResultsByKey: [String: [Int]] = [:]
    var recordSearchTotalsByKey: [String: Int] = [:]
    func normalizedQuery(_ query: String) -> String { query }
    func recordFilters(for id: String) -> GroupRecordFilters { currentFilters }
    func context(for id: String) -> Int { 0 }
    func recordSearchRequest(for query: String, groupId: String) -> GroupRecordFilters { currentFilters }
    func group(id: String) -> WalkGroup? { currentGroup }
    func replaceGroup(_ group: WalkGroup) { currentGroup = group }
    func applyRefreshedToken(_ token: String?) {}
    func trackSource(_ source: Int, for group: WalkGroup) {}
    func clearRecordCaches(for id: String) {}
    func recordListKey(groupId: String, search: String) -> String { search }
    func recordFailure(operation: String, intent: Intent, disposition: Disposition, failure: Failure) {}
    func searchRecords(groupId: String, query: String) async {}
    func refreshGroupBalances(_ id: String) async {}
    func refreshSettlementSuggestion(groupId: String) async {}
STORE_METHODS
}
struct ScrollTitle { var resets = 0; mutating func reset() { resets += 1 } }
enum Edge { case top }
struct ScrollPosition { func scrollTo(edge: Edge) {} }
@MainActor final class View {
    let store: Store
    init(_ store: Store) { self.store = store }
    var groupId = "g"
    var recordQuery = Query()
    var recordRefreshID: UUID?
    var isRefreshingRecords = false
    var hasLoadedRecords = true
    var hasCompletedInitialLoad = false
    var displayedFilters: GroupRecordFilters?
    var needsQueryScrollToTop = false
    var scrollTitle = ScrollTitle()
    var scrollPosition = ScrollPosition()
VIEW_METHOD
}
@main struct Runner {
    @MainActor static func until(_ predicate: () -> Bool) async {
        for _ in 0..<20_000 { if predicate() { return }; await Task.yield() }
        fatalError("Refresh failed to reach expected state")
    }
    @MainActor static func main() async {
        // SwiftUI cancellation used to return before clearing loading forever.
        let store = Store(), view = View(Store())
        let cancelled = Task { await view.refreshGroupContent() }
        await until { view.store.ledgerRepository.requests.count == 1 }
        precondition(view.isRefreshingRecords)
        cancelled.cancel()
        view.store.ledgerRepository.finish(0)
        await cancelled.value
        precondition(!view.isRefreshingRecords && view.recordRefreshID == nil, "Cancelled refresh must end loading")

        // An old cancelled search must not clear the newer search's task/indicator.
        let ui = View(store)
        let old = Task { await ui.refreshGroupContent() }
        await until { store.ledgerRepository.requests.count == 1 }
        old.cancel()
        ui.recordQuery.text = "new"
        let new = Task { await ui.refreshGroupContent() }
        await until { store.ledgerRepository.requests.count == 2 }
        store.ledgerRepository.finish(0)
        await old.value
        precondition(ui.isRefreshingRecords && store.groupContentRefreshTasks["g"] != nil)
        store.ledgerRepository.finish(1)
        await new.value
        precondition(!ui.isRefreshingRecords && ui.hasCompletedInitialLoad)
        precondition(ui.scrollTitle.resets == 1, "Submitted search must still reposition to top")
        precondition(store.groupContentRefreshTasks.isEmpty && store.groupContentRefreshIDs.isEmpty)

        // Pull-to-refresh keeps existing rows visible; failures still terminate it.
        let resetsBeforePull = ui.scrollTitle.resets
        let pull = Task { await ui.refreshGroupContent(showLoading: false) }
        await until { store.ledgerRepository.requests.count == 3 }
        precondition(!ui.isRefreshingRecords && ui.recordRefreshID != nil)
        store.ledgerRepository.finish(2, fail: true)
        await pull.value
        precondition(ui.recordRefreshID == nil)
        precondition(ui.scrollTitle.resets == resetsBeforePull, "Pull refresh with a search must not issue scrollTo while the native refresh control collapses")

        // Identical queries share one fetch. Filter changes require a new fetch.
        store.preloadGroupContent("g")
        await until { store.ledgerRepository.requests.count == 4 }
        let sharedID = store.groupContentRefreshIDs["g"]
        store.preloadGroupContent("g")
        precondition(sharedID == store.groupContentRefreshIDs["g"])
        store.currentFilters.category = 1
        store.preloadGroupContent("g")
        await until { store.ledgerRepository.requests.count == 5 }
        precondition(sharedID != store.groupContentRefreshIDs["g"])
        store.ledgerRepository.finish(3)
        store.ledgerRepository.finish(4)
        await until { store.groupContentRefreshTasks.isEmpty }
        precondition(store.ledgerRepository.filters[4].category == 1)

        // Even if cancellation reaches the worker, its registry entry is removed.
        store.preloadGroupContent("g")
        await until { store.ledgerRepository.requests.count == 6 }
        store.groupContentRefreshTasks["g"]!.cancel()
        store.ledgerRepository.finish(5)
        await until { store.groupContentRefreshTasks.isEmpty }

        // Old detail arriving after a pin acknowledgement must preserve that pin.
        let detail = Task { await store.refreshGroup("g") }
        await until { store.ledgerRepository.requests.count == 7 }
        store.groupListRevision += 2
        store.currentGroup.pinnedAt = 42
        store.ledgerRepository.finish(6)
        await detail.value
        precondition(store.currentGroup.pinnedAt == 42)
        let fresh = Task { await store.refreshGroup("g") }
        await until { store.ledgerRepository.requests.count == 8 }
        store.ledgerRepository.finish(7, pin: 100)
        await fresh.value
        precondition(store.currentGroup.pinnedAt == 100, "Fresh response must reconcile server state")

        // Refresh requested during a write waits for its ack instead of disappearing.
        store.pendingGroupPins["g"] = UUID()
        var resumed = false
        let waiting = Task { await store.waitForPendingGroupPins(); resumed = true }
        await until { store.groupPinWaiters.count == 1 }
        precondition(!resumed)
        store.pendingGroupPins.removeAll()
        store.resumeGroupPinWaiters()
        await waiting.value
        precondition(resumed && store.groupPinWaiters.isEmpty)
        print("PASS: cancelled loading cleanup; overlapping queries; pull refresh/failure; coalescing; filter changes; cancelled worker cleanup; stale detail pin protection; fresh server reconciliation; refresh waits for pin ack")
    }
}
'''.replace('STORE_METHODS', methods).replace('VIEW_METHOD', view_method)
with tempfile.TemporaryDirectory(prefix='walkcalc-refresh-lifecycle-') as directory:
    runner = Path(directory) / 'Runner.swift'
    runner.write_text(harness)
    binary = Path(directory) / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(runner), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
