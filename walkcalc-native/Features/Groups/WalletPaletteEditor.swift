#if DEBUG
import SwiftUI
import UIKit

struct WalletPaletteEditor: View {
    @WalletPaletteSettings private var palette: WalletPalette
    @State private var editMode: EditMode = .inactive
    @State private var confirmReset = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                ForEach(palette.entries) { entry in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(entry.color.color)
                            .frame(width: 44, height: 32)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                            }
                            .accessibilityHidden(true)
                        ColorPicker(selection: colorBinding(id: entry.id), supportsOpacity: false) {
                            Text(entry.color.hex).monospaced()
                        }
                    }
                    .frame(minHeight: 44)
                    .deleteDisabled(palette.entries.count == 1)
                }
                .onMove { source, destination in
                    palette.entries.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { indices in
                    guard indices.count < palette.entries.count else { return }
                    palette.entries.remove(atOffsets: indices)
                }
                Button("Add Color") {
                    let color = WalletRGB(hex: 0xB9AFEA)
                    palette.entries.append(WalletPaletteEntry(id: UUID().uuidString, color: color))
                    editMode = .inactive
                }
            } header: {
                Text("\(palette.entries.count) Colors")
            } footer: {
                Text("Tap a color to edit. Use Edit to reorder; swipe to delete. Changes save automatically for all group wallets on this device.")
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section {
                Button(copied ? "Copied" : "Copy JSON") {
                    UIPasteboard.general.string = palette.parameterSummary
                    copied = true
                }
                Button("Reset Palette", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Each swatch shows one base color. Wallet color adjustments still apply.")
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .navigationTitle("Color Palette")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .confirmationDialog("Replace this palette with the eight default colors?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Palette", role: .destructive) { palette = .defaults }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: palette) { _, _ in copied = false }
    }

    private func colorBinding(id: String) -> Binding<Color> {
        Binding(get: {
            guard let entry = palette.entries.first(where: { $0.id == id }) else { return .clear }
            return entry.color.color
        }, set: { color in
            guard let index = palette.entries.firstIndex(where: { $0.id == id }),
                  let converted = UIColor(color).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                    intent: .defaultIntent, options: nil),
                  let components = converted.components, components.count >= 3 else { return }
            let rgb = WalletRGB(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
            palette.entries[index].color = rgb
        })
    }
}
#endif
