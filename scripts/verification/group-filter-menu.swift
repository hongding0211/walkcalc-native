// App-model shims only; the runner compiles the unchanged production menu
// implementation against real UIKit/SwiftUI via Mac Catalyst (no simulator).
import UIKit
func L(_ value: String) -> String { value }
struct GroupRecordFilters: Equatable {
    var currencyCodes: Set<String> = []
    var onlyRelatedToMe = false
    var categoryIds: Set<String> = []
    var isActive: Bool { onlyRelatedToMe || !currencyCodes.isEmpty || !categoryIds.isEmpty }
    var summary: String { currencyCodes.sorted().joined(separator: ",") }
}
enum AppTheme { case mono, blue, pink, yellow, green
    var accentUIColor: UIColor { .systemBlue }
}
enum CurrencyCatalog {
    struct Info { let name: String }
    static func currencyInfo(for code: String) -> Info { Info(name: code) }
}

struct MenuCategory { let id: String; let titleKey: String; let symbol: String }
let expenseCategories = [MenuCategory(id: "food", titleKey: "Meal", symbol: "fork.knife"), MenuCategory(id: "traffic", titleKey: "Transport", symbol: "tram.fill")]

final class ClosingAnimator: NSObject, UIContextMenuInteractionAnimating {
    var previewViewController: UIViewController? { nil }
    var completions: [() -> Void] = []
    func addAnimations(_ animations: @escaping () -> Void) {}
    func addCompletion(_ completion: @escaping () -> Void) { completions.append(completion) }
    func finish() { completions.forEach { $0() } }
}

@MainActor
func verifyGroupFilterMenu() {
    var scopeSelections: [Bool] = []
    var currencySelections: [Set<String>] = []
    var categorySelections: [Set<String>] = []
    func value(_ filters: GroupRecordFilters, codes: [String] = ["CNY", "USD"]) -> GroupRecordFilterToolbar {
        GroupRecordFilterToolbar(groupId: "test-group", filters: filters,
            currencyCodes: codes, theme: .mono,
            onRelatedChange: { scopeSelections.append($0) },
            onCurrencyChange: { currencySelections.append($0) },
            onCategoryChange: { categorySelections.append($0) })
    }
    func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        precondition(condition(), name)
        print("PASS: \(name)")
    }
    let coordinator = NativeGroupFilterButton.Coordinator(value: value(GroupRecordFilters()))
    let button = GroupFilterButton(type: .system)
    button.showsMenuAsPrimaryAction = true
    coordinator.button = button
    coordinator.installMenu()
    let root = button.menu!
    let interaction = button.contextMenuInteraction!
    let first = UIContextMenuConfiguration(identifier: "first" as NSString, previewProvider: nil)
    button.contextMenuInteraction(interaction, willDisplayMenuFor: first, animator: nil)
    let firstPresentation = button.menuPresentation
    let related = coordinator.menuItems()[1] as! UIAction
    button.sendAction(related)
    check("scope change publishes immediately", scopeSelections == [true])
    check("selection does not replace the presented root", button.menu === root)
    check("immediate reopen sees new scope", (coordinator.menuItems()[1] as! UIAction).state == .on)

    let animator = ClosingAnimator()
    button.contextMenuInteraction(interaction, willEndFor: first, animator: animator)
    // Simulate refreshed group currencies arriving while the close animation runs.
    coordinator.update(value(GroupRecordFilters(onlyRelatedToMe: true), codes: ["CNY", "EUR", "USD"]))
    check("refresh during dismissal preserves root", button.menu === root)
    let second = UIContextMenuConfiguration(identifier: "second" as NSString, previewProvider: nil)
    button.contextMenuInteraction(interaction, willDisplayMenuFor: second, animator: nil)
    check("reopen has a distinct update generation", button.menuPresentation != firstPresentation)
    animator.finish()
    check("old animation completion preserves reopened root", button.menu === root && button.isMenuPresented)
    button.contextMenuInteraction(interaction, willEndFor: first, animator: nil)
    check("late end for old configuration cannot end new one", button.isMenuPresented)

    let currencyMenu = coordinator.menuItems()[2] as! UIMenu
    check("refresh supplies newly available currencies", currencyMenu.children.count == 4)
    let cny = currencyMenu.children[1] as! UIAction
    check("currency actions keep menu open", cny.attributes.contains(.keepsMenuPresented))
    button.sendAction(cny)
    let nextCurrencies = coordinator.menuItems()[2] as! UIMenu
    button.sendAction(nextCurrencies.children[2] as! UIAction)
    check("rapid currency additions accumulate", currencySelections.last == Set(["CNY", "EUR"]))
    check("currency selections preserve related scope", coordinator.value.filters.onlyRelatedToMe)
    check("refresh and multi-select preserve root", button.menu === root)
    let categories = coordinator.menuItems()[3] as! UIMenu
    check("category actions keep menu open", (categories.children[1] as! UIAction).attributes.contains(.keepsMenuPresented))
    button.sendAction(categories.children[1] as! UIAction)
    button.sendAction((coordinator.menuItems()[3] as! UIMenu).children[2] as! UIAction)
    check("multiple category choices accumulate", categorySelections.last == Set(["food", "traffic"]))
    check("category choices preserve other filters", coordinator.value.filters.currencyCodes == Set(["CNY", "EUR"]) && coordinator.value.filters.onlyRelatedToMe)
    check("categories reuse stable root", button.menu === root)
    let selectedCategories = coordinator.menuItems()[3] as! UIMenu
    check("category selection states are current", (selectedCategories.children[1] as! UIAction).state == .on && (selectedCategories.children[2] as! UIAction).state == .on)
    button.sendAction(selectedCategories.children[0] as! UIAction)
    check("category All only clears categories", coordinator.value.filters.categoryIds.isEmpty && coordinator.value.filters.currencyCodes == Set(["CNY", "EUR"]) && coordinator.value.filters.onlyRelatedToMe)
    let selectedCurrencies = coordinator.menuItems()[2] as! UIMenu
    check("selected currency states are current", (selectedCurrencies.children[1] as! UIAction).state == .on && (selectedCurrencies.children[2] as! UIAction).state == .on)
    button.sendAction(selectedCurrencies.children[0] as! UIAction)
    check("All clears currencies without clearing scope", coordinator.value.filters.currencyCodes.isEmpty && coordinator.value.filters.onlyRelatedToMe)
    button.contextMenuInteraction(interaction, willEndFor: second, animator: nil)
    check("current presentation ends normally", !button.isMenuPresented)
    print("GROUP_FILTER_MENU_VERIFICATION: PASSED")
}
MainActor.assumeIsolated { verifyGroupFilterMenu() }
