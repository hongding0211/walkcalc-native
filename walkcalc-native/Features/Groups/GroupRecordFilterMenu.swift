import SwiftUI
import UIKit

struct GroupRecordFilterToolbar: View, Equatable {
    let groupId: String
    let filters: GroupRecordFilters
    let currencyCodes: [String]
    let theme: AppTheme
    let onRelatedChange: (Bool) -> Void
    let onCurrencyChange: (Set<String>) -> Void
    let onCategoryChange: (Set<String>) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.groupId == rhs.groupId && lhs.filters == rhs.filters
            && lhs.currencyCodes == rhs.currencyCodes && lhs.theme == rhs.theme
    }

    var body: some View {
        NativeGroupFilterButton(value: self)
            .frame(width: 32, height: 32)
    }
}

private struct NativeGroupFilterButton: UIViewRepresentable {
    let value: GroupRecordFilterToolbar

    func makeCoordinator() -> Coordinator { Coordinator(value: value) }

    func makeUIView(context: Context) -> GroupFilterButton {
        let button = GroupFilterButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.accessibilityLabel = L("Filters")
        context.coordinator.button = button
        button.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak coordinator = context.coordinator] (_: GroupFilterButton, _: UITraitCollection) in
            coordinator?.updateAppearance()
        }
        context.coordinator.installMenu()
        context.coordinator.updateAppearance()
        return button
    }

    func updateUIView(_ button: GroupFilterButton, context: Context) {
        context.coordinator.update(value)
    }

    final class Coordinator {
        var value: GroupRecordFilterToolbar
        weak var button: GroupFilterButton?
        private let currencyMenuID = UIMenu.Identifier("group-filter-currency")
        private let allCurrenciesActionID = UIAction.Identifier("group-filter-currency-all")
        private let categoryMenuID = UIMenu.Identifier("group-filter-category")
        private let allCategoriesActionID = UIAction.Identifier("group-filter-category-all")
        private let allActionID = UIAction.Identifier("group-filter-all")
        private let relatedActionID = UIAction.Identifier("group-filter-related")

        init(value: GroupRecordFilterToolbar) { self.value = value }

        private var subtitle: String {
            let codes = value.filters.currencyCodes.sorted()
            guard !codes.isEmpty else { return L("All currencies") }
            let visible = codes.prefix(2).joined(separator: ", ")
            return codes.count > 2 ? "\(visible), … +\(codes.count - 2)" : visible
        }

        private var categorySubtitle: String {
            let names = expenseCategories.filter { value.filters.categoryIds.contains($0.id) }.map { L($0.titleKey) }
            guard !names.isEmpty else { return L("All categories") }
            let visible = names.prefix(2).joined(separator: ", ")
            return names.count > 2 ? "\(visible), … +\(names.count - 2)" : visible
        }

        func update(_ next: GroupRecordFilterToolbar) {
            let menuChanged = value.groupId != next.groupId || value.filters != next.filters
                || value.currencyCodes != next.currencyCodes
            let appearanceChanged = value.filters.isActive != next.filters.isActive || value.theme != next.theme
            let groupChanged = value.groupId != next.groupId
            value = next
            if groupChanged { button?.contextMenuInteraction?.dismissMenu() }
            if menuChanged { updateMenu() }
            if appearanceChanged { updateAppearance() }
        }

        func installMenu() {
            // Install the root once. Replacing UIButton.menu during dismissal
            // or a rapid reopen can dismiss the next presentation as well.
            let items = UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.menuItems() ?? [])
            }
            button?.menu = UIMenu(identifier: UIMenu.Identifier("group-record-filters"), children: [items])
        }

        func menuItems() -> [UIMenuElement] {
            // One scope is always selected so UIKit keeps its native checkmark column.
            let all = UIAction(
                title: L("All"),
                image: UIImage(systemName: "tray.full"),
                identifier: allActionID,
                state: value.filters.onlyRelatedToMe ? .off : .on
            ) { [weak self] _ in
                self?.selectRelatedScope(false)
            }
            let related = UIAction(
                title: L("Related to me"),
                image: UIImage(systemName: "person.crop.circle"),
                identifier: relatedActionID,
                state: value.filters.onlyRelatedToMe ? .on : .off
            ) { [weak self] _ in
                self?.selectRelatedScope(true)
            }
            let allCurrencies = UIAction(
                title: L("All"),
                identifier: allCurrenciesActionID,
                attributes: .keepsMenuPresented,
                state: value.filters.currencyCodes.isEmpty ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                value = replacingFilters { $0.currencyCodes = [] }
                updateMenu()
                updateAppearance()
                value.onCurrencyChange([])
            }
            let currencies = value.currencyCodes.map { code in
                UIAction(
                    title: "\(code) · \(CurrencyCatalog.currencyInfo(for: code).name)",
                    identifier: UIAction.Identifier("group-filter-currency-\(code)"),
                    attributes: .keepsMenuPresented,
                    state: value.filters.currencyCodes.contains(code) ? .on : .off
                ) { [weak self] _ in
                    guard let self else { return }
                    value = replacingFilters {
                        if $0.currencyCodes.contains(code) { $0.currencyCodes.remove(code) }
                        else { $0.currencyCodes.insert(code) }
                    }
                    updateMenu()
                    updateAppearance()
                    value.onCurrencyChange(value.filters.currencyCodes)
                }
            }
            let currencyMenu = UIMenu(
                title: L("Currency"), image: UIImage(systemName: "dollarsign.circle"),
                identifier: currencyMenuID, children: [allCurrencies] + currencies
            )
            currencyMenu.subtitle = subtitle
            let allCategories = UIAction(
                title: L("All"), identifier: allCategoriesActionID,
                attributes: .keepsMenuPresented,
                state: value.filters.categoryIds.isEmpty ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                value = replacingFilters { $0.categoryIds = [] }
                updateMenu()
                updateAppearance()
                value.onCategoryChange([])
            }
            let categories = expenseCategories.map { category in
                UIAction(
                    title: L(category.titleKey), image: UIImage(systemName: category.symbol),
                    identifier: UIAction.Identifier("group-filter-category-\(category.id)"),
                    attributes: .keepsMenuPresented,
                    state: value.filters.categoryIds.contains(category.id) ? .on : .off
                ) { [weak self] _ in
                    guard let self else { return }
                    value = replacingFilters {
                        if $0.categoryIds.contains(category.id) { $0.categoryIds.remove(category.id) }
                        else { $0.categoryIds.insert(category.id) }
                    }
                    updateMenu()
                    updateAppearance()
                    value.onCategoryChange(value.filters.categoryIds)
                }
            }
            let categoryMenu = UIMenu(
                title: L("Category"), image: UIImage(systemName: "tag"),
                identifier: categoryMenuID, children: [allCategories] + categories
            )
            categoryMenu.subtitle = categorySubtitle
            return [all, related, currencyMenu, categoryMenu]
        }

        private func selectRelatedScope(_ selected: Bool) {
            value = replacingFilters { $0.onlyRelatedToMe = selected }
            // The uncached provider reads this value on the next open, even
            // before the previous dismissal or network refresh has completed.
            updateMenu()
            updateAppearance()
            value.onRelatedChange(selected)
        }

        private func replacingFilters(_ update: (inout GroupRecordFilters) -> Void) -> GroupRecordFilterToolbar {
            var filters = value.filters
            update(&filters)
            return GroupRecordFilterToolbar(
                groupId: value.groupId, filters: filters, currencyCodes: value.currencyCodes,
                theme: value.theme, onRelatedChange: value.onRelatedChange, onCurrencyChange: value.onCurrencyChange,
                onCategoryChange: value.onCategoryChange
            )
        }

        private func updateMenu() {
            button?.accessibilityValue = value.filters.summary
            guard let button, button.isMenuPresented else { return }
            let presentation = button.menuPresentation
            // Preserve the displayed menu's identity and unchanged subtitle.
            // UIKit supplies a mutable copy of each visible submenu here.
            // Apply after UIKit finishes dispatching the selected action.
            DispatchQueue.main.async { [weak self, weak button] in
                guard let self, let button, button.isMenuPresented,
                      button.menuPresentation == presentation else { return }
                UIView.performWithoutAnimation {
                    button.contextMenuInteraction?.updateVisibleMenu { [self] menu in
                        self.updatedMenu(menu)
                    }
                }
            }
        }

        private func updatedMenu(_ menu: UIMenu) -> UIMenu {
            let children = menu.children.map { element -> UIMenuElement in
                if let submenu = element as? UIMenu {
                    return updatedMenu(submenu)
                }
                guard let action = element as? UIAction else { return element }
                let selected: Bool
                if action.identifier == allActionID {
                    selected = !value.filters.onlyRelatedToMe
                } else if action.identifier == relatedActionID {
                    selected = value.filters.onlyRelatedToMe
                } else if action.identifier == allCurrenciesActionID {
                    selected = value.filters.currencyCodes.isEmpty
                } else if action.identifier == allCategoriesActionID {
                    selected = value.filters.categoryIds.isEmpty
                } else {
                    selected = value.filters.categoryIds.contains {
                        action.identifier == UIAction.Identifier("group-filter-category-\($0)")
                    } || value.filters.currencyCodes.contains {
                        action.identifier == UIAction.Identifier("group-filter-currency-\($0)")
                    }
                }
                let state: UIMenuElement.State = selected ? .on : .off
                guard action.state != state else { return action }
                let updated = action.copy() as! UIAction
                updated.state = state
                return updated
            }
            let changedChildren = zip(menu.children, children).contains { $0 !== $1 }
            let nextSubtitle = menu.identifier == currencyMenuID ? subtitle
                : menu.identifier == categoryMenuID ? categorySubtitle : menu.subtitle
            let changedSubtitle = menu.subtitle != nextSubtitle
            guard changedChildren || changedSubtitle else { return menu }
            let updated = menu.replacingChildren(children)
            if changedSubtitle { updated.subtitle = nextSubtitle }
            return updated
        }

        func updateAppearance() {
            guard let button else { return }
            button.accessibilityValue = value.filters.summary
            button.selectionBackground.backgroundColor = value.filters.isActive ? value.theme.accentUIColor : .clear
            // The menu inherits the control tint. Invert only the toolbar
            // image, so its selected state cannot recolor the open menu.
            button.tintColor = .label
            let iconColor: UIColor
            if !value.filters.isActive {
                iconColor = .label
            } else {
                switch value.theme {
                case .mono: iconColor = .systemBackground
                case .yellow, .green: iconColor = .black
                case .blue, .pink: iconColor = .white
                }
            }
            let image = UIImage(systemName: "line.3.horizontal.decrease", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))?
                .withTintColor(iconColor.resolvedColor(with: button.traitCollection), renderingMode: .alwaysOriginal)
            button.setImage(image, for: .normal)
        }
    }
}

private final class GroupFilterButton: UIButton {
    let selectionBackground = UIView()
    private(set) var isMenuPresented = false
    private(set) var menuPresentation = 0
    private weak var presentedConfiguration: UIContextMenuConfiguration?

    override init(frame: CGRect) {
        super.init(frame: frame)
        selectionBackground.isUserInteractionEnabled = false
        selectionBackground.layer.cornerRadius = 16
        insertSubview(selectionBackground, at: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        selectionBackground.frame = CGRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)
        sendSubviewToBack(selectionBackground)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        menuPresentation += 1
        presentedConfiguration = configuration
        isMenuPresented = true
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        if presentedConfiguration === configuration {
            isMenuPresented = false
            presentedConfiguration = nil
        }
        // No animation-completion callback may replace the menu: a newer
        // presentation may already exist by the time that callback runs.
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    }
}
