#if DEBUG
import SwiftUI

struct AppearanceDebugView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss
    @State private var previewMode = 0
    @AppStorage(WalletHeightLimit.storageKey) private var walletHeightFraction = WalletHeightLimit.defaultFraction

    var body: some View {
        Form {
            Section {
                Picker("预览模式", selection: $previewMode) {
                    Text("系统").tag(0)
                    Text("浅色").tag(1)
                    Text("深色").tag(2)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("切换模式可分别调整浅色与深色配色。修改即时生效并保存在本机。")
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section("类别图标") {
                CategoryIconDebugControls()
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section {
                MoneyColorDebugControls()
            } header: {
                Text("金额颜色")
            } footer: {
                Text("正负颜色分别调整，浅色与深色分别保存。")
            }
            .listRowBackground(SoftLedgerTheme.formPaper)

            Section("卡包") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最大高度占比")
                        Spacer()
                        Text(walletHeightFraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $walletHeightFraction, in: WalletHeightLimit.fractionRange, step: 0.01) {
                        Text("卡包最大高度占比")
                    }
                    Text("由系统宽度类型决定：紧凑宽度保持原比例；常规宽度仅在卡包自然高度超过上限时缩短。默认 30%；大字体优先保持可读。修改自动保存在本机。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("恢复默认高度") {
                        walletHeightFraction = WalletHeightLimit.defaultFraction
                    }
                }
                NavigationLink("Color Palette") { WalletPaletteEditor() }
                NavigationLink("卡包调节") {
                    List(store.groups) { group in
                        NavigationLink(group.name) { GroupWalletTuningView(groupId: group.id) }
                    }
                    .overlay {
                        if store.groups.isEmpty {
                            ContentUnavailableView("暂无群组", systemImage: "rectangle.stack")
                        }
                    }
                    .navigationTitle("选择预览群组")
                }
            }
            .listRowBackground(SoftLedgerTheme.formPaper)
        }
        .scrollContentBackground(.hidden)
        .background(SoftLedgerTheme.canvas)
        .navigationTitle("调试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Done")) { dismiss() }
            }
        }
        .preferredColorScheme(previewMode == 0 ? nil : previewMode == 1 ? .light : .dark)
    }
}
#endif
