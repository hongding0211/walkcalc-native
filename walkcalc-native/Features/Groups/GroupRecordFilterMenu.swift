import SwiftUI

struct GroupRecordFilterToolbar: View {
    // The circular symbol includes padding: these sizes align the inner three-line glyph.
    @ScaledMetric(relativeTo: .body) private var activeSymbolSize = 36
    @ScaledMetric(relativeTo: .body) private var inactiveSymbolSize = 22
    let groupId: String
    let filters: GroupRecordFilters
    let currencyCodes: [String]
    let theme: AppTheme
    let onRelatedChange: (Bool) -> Void
    let onCurrencyChange: (Set<String>) -> Void
    let onCategoryChange: (Set<String>) -> Void

    private var currencySummary: String {
        summary(filters.currencyCodes.sorted(), empty: L("All currencies"))
    }

    private var categorySummary: String {
        summary(expenseCategories.filter { filters.categoryIds.contains($0.id) }.map { L($0.titleKey) }, empty: L("All categories"))
    }

    private func summary(_ values: [String], empty: String) -> String {
        guard !values.isEmpty else { return empty }
        let visible = values.prefix(2).joined(separator: ", ")
        return values.count > 2 ? "\(visible), … +\(values.count - 2)" : visible
    }

    var body: some View {
        Menu {
            Picker(L("Filters"), selection: Binding(get: { filters.onlyRelatedToMe }, set: onRelatedChange)) {
                Label(L("All"), systemImage: "tray.full").tag(false)
                Label(L("Related to me"), systemImage: "person.crop.circle").tag(true)
            }
            .pickerStyle(.inline)
            Menu {
                Toggle(L("All"), isOn: Binding(get: { filters.currencyCodes.isEmpty }, set: { _ in onCurrencyChange([]) }))
                    .menuActionDismissBehavior(.disabled)
                ForEach(currencyCodes, id: \.self) { code in
                    Toggle("\(code) · \(CurrencyCatalog.currencyInfo(for: code).name)", isOn: membership(code, in: filters.currencyCodes, update: onCurrencyChange))
                        .menuActionDismissBehavior(.disabled)
                }
            } label: {
                Label(L("Currency"), systemImage: "dollarsign.circle")
                Text(currencySummary)
            }
            Menu {
                Toggle(L("All"), isOn: Binding(get: { filters.categoryIds.isEmpty }, set: { _ in onCategoryChange([]) }))
                    .menuActionDismissBehavior(.disabled)
                ForEach(expenseCategories, id: \.id) { category in
                    Toggle(isOn: membership(category.id, in: filters.categoryIds, update: onCategoryChange)) {
                        Label(L(category.titleKey), systemImage: category.symbol)
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            } label: {
                Label(L("Category"), systemImage: "tag")
                Text(categorySummary)
            }
        } label: {
            Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .resizable()
                .scaledToFit()
                .frame(width: filters.isActive ? activeSymbolSize : inactiveSymbolSize,
                       height: filters.isActive ? activeSymbolSize : inactiveSymbolSize)
        }
        .menuOrder(.fixed)
        .accessibilityLabel(L("Filters"))
        .accessibilityValue(filters.summary)
    }

    private func membership(_ id: String, in selected: Set<String>, update: @escaping (Set<String>) -> Void) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { enabled in
            var next = selected
            if enabled { next.insert(id) } else { next.remove(id) }
            update(next)
        })
    }
}
