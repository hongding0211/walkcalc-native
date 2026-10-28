#!/usr/bin/env python3
"""Verify the actual store/Home pin methods against suspended API responses."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
store = (root / "walkcalc-native/App/WalkcalcStore.swift").read_text()
home = (root / "walkcalc-native/Features/Home/HomeViews.swift").read_text()
models = (root / "walkcalc-native/Core/Models/Models.swift").read_text()
actions = store[store.index("    func setGroupPinned("):store.index("    func group(id:")]
home_action = home[home.index("    private func togglePin("):home.index("    private func archive(")].replace("private func", "func", 1)
comparator = models[models.index("    static func homePrecedes("):models.index("    static func mergingLocalGroups(")]
harness = r'''
import Foundation
struct WalkGroup {
    var id: String
    var pinnedAt: TimeInterval?
    var modifiedAt: TimeInterval = 0
    var isPinned: Bool { pinnedAt != nil }
COMPARATOR
}
struct StoreActionResult {
    var success: Bool
    var message: String?
    static var success: Self { Self(success: true) }
    static func failure(_ message: String?) -> Self { Self(success: false, message: message) }
}
struct PinState { var pinnedAt: TimeInterval? }
struct Response { var value: PinState?; var refreshedToken: String? }
enum Failure: Error { case failed }
@MainActor final class Repository {
    var saves: [String: CheckedContinuation<Result<Response, Failure>, Never>] = [:]
    var requestCount = 0
    func pinGroup(code: String, isPinned: Bool, context: Int) async -> Result<Response, Failure> {
        requestCount += 1
        return await withCheckedContinuation { saves[code] = $0 }
    }
    func finish(_ code: String, _ result: Result<Response, Failure>) {
        saves.removeValue(forKey: code)!.resume(returning: result)
    }
}
@MainActor final class Store {
    let ledgerRepository = Repository()
    var groups: [WalkGroup] = []
    var pendingGroupPins: [String: UUID] = [:]
    func resumeGroupPinWaiters() {}
    var groupListRevision = 0
    var completedGroupPinUpdates = 0
    var needsGroupOrderRefresh = false
    var isFixtureMode = false
    func group(id: String) -> WalkGroup? { groups.first { $0.id == id } }
    func context(for id: String) -> Int { 0 }
    func applyRefreshedToken(_ token: String?) {}
    func actionFailure(operation: String, failure: Failure) -> StoreActionResult { .failure("Save failed") }
ACTIONS
}
func L(_ text: String) -> String { text }
@MainActor final class Home {
    let store = Store()
    var pendingGroupAction: String?
    var pinError: String?
HOME_ACTION
}
@main struct Runner {
    @MainActor static func until(_ predicate: () -> Bool) async {
        for _ in 0..<10_000 {
            if predicate() { return }
            await Task.yield()
        }
        fatalError("Operation did not reach expected state")
    }
    @MainActor static func main() async {
        let home = Home()
        let store = home.store
        store.groups = [.init(id: "pinned", pinnedAt: 10), .init(id: "a", modifiedAt: 20), .init(id: "b", modifiedAt: 10)]
        let originalRow = store.group(id: "b")!
        let first = Task { await home.togglePin(originalRow.id) }
        await until { store.ledgerRepository.saves["b"] != nil }
        precondition(store.group(id: "b")!.isPinned, "Pin must appear before the response")
        precondition(store.groups.map(\.id) == ["pinned", "b", "a"])
        precondition(home.pendingGroupAction == nil, "Pin must never show the blocking row spinner")
        _ = await store.setGroupPinned(false, groupId: "b")
        precondition(store.ledgerRepository.requestCount == 1, "Same-group writes must not race")
        store.ledgerRepository.finish("b", .success(Response(value: PinState(pinnedAt: 30))))
        await first.value
        precondition(store.group(id: "b")!.pinnedAt == 30)
        precondition(store.pendingGroupPins.isEmpty)
        let unpin = Task { await home.togglePin(originalRow.id) }
        await until { store.ledgerRepository.saves["b"] != nil }
        precondition(!store.group(id: "b")!.isPinned, "Unpin must appear before the response")
        precondition(store.groups.map(\.id) == ["pinned", "a", "b"])
        store.ledgerRepository.finish("b", .failure(.failed))
        await unpin.value
        precondition(store.group(id: "b")!.pinnedAt == 30, "Failed write must restore prior pin")
        precondition(store.groups.map(\.id) == ["pinned", "b", "a"])
        precondition(store.pendingGroupPins.isEmpty && home.pinError == "Save failed")
        let savedUnpin = Task { await home.togglePin(originalRow.id) }
        await until { store.ledgerRepository.saves["b"] != nil }
        store.ledgerRepository.finish("b", .success(Response(value: PinState(pinnedAt: nil))))
        await savedUnpin.value
        precondition(!store.group(id: "b")!.isPinned && store.pendingGroupPins.isEmpty)
        let repin = Task { await home.togglePin(originalRow.id) }
        await until { store.ledgerRepository.saves["b"] != nil }
        store.ledgerRepository.finish("b", .success(Response(value: PinState(pinnedAt: 40))))
        await repin.value
        precondition(store.group(id: "b")!.pinnedAt == 40)
        let oldSession = Task { await store.setGroupPinned(false, groupId: "b") }
        await until { store.ledgerRepository.saves["b"] != nil }
        store.pendingGroupPins = [:]
        store.groups = [.init(id: "b", pinnedAt: 99)]
        store.ledgerRepository.finish("b", .success(Response(value: PinState(pinnedAt: nil))))
        _ = await oldSession.value
        precondition(store.group(id: "b")!.pinnedAt == 99, "Old session must not mutate new state")
        print("PASS: optimistic Pin/Unpin; no row spinner; oldest-first order; duplicate guard; rollback; stale session ignored")
    }
}
'''.replace("COMPARATOR", comparator).replace("HOME_ACTION", home_action).replace("ACTIONS", actions)
with tempfile.TemporaryDirectory(prefix="walkcalc-pin-lifecycle-") as directory:
    runner = Path(directory) / "Runner.swift"
    runner.write_text(harness)
    binary = Path(directory) / "verify"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(runner), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
