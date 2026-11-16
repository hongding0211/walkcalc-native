#if DEBUG
import SwiftUI

// Standalone system-menu comparison: no store, refresh, representable or menu updates.
struct NativeMenuProbe: View {
    @State private var selected = Set<String>()
    var body: some View {
        NavigationSplitView {
            Text("Sidebar")
        } detail: {
            Text("Native toolbar menu comparison")
                .navigationTitle("Menu probe")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("All") { selected = [] }
                            Menu {
                                ForEach(expenseCategories, id: \.id) { category in
                                    Toggle(isOn: Binding(get: { selected.contains(category.id) }, set: { enabled in
                                        if enabled { selected.insert(category.id) }
                                        else { selected.remove(category.id) }
                                    })) {
                                        Label(L(category.titleKey), systemImage: category.symbol)
                                    }
                                    .menuActionDismissBehavior(.disabled)
                                }
                            } label: {
                                Label("Category", systemImage: "tag")
                            }
                        } label: {
                            Label("Filters", systemImage: "line.3.horizontal.decrease")
                        }
                    }
                }
        }
    }
}
#endif
