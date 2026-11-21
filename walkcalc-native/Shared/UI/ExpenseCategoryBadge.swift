import SwiftUI

#if DEBUG
enum CategoryIconDebugSettings {
    static let storageKey = "debug.categoryIcons.useEmoji"
    // Separate keys adopt the approved light/dark baselines without reviving
    // the old shared saturation value saved during the first comparison.
    static let lightSaturationKey = "debug.categoryIcons.saturation.v3.light"
    static let darkSaturationKey = "debug.categoryIcons.saturation.v3.dark"
    static let foregroundKey = "debug.categoryIcons.foreground"
    static let lightDepthKey = "debug.categoryIcons.foregroundDepth.v2.light"
    static let darkDepthKey = "debug.categoryIcons.foregroundDepth.v2.dark"
}

@propertyWrapper
private struct CategorySaturationSettings: DynamicProperty {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CategoryIconDebugSettings.lightSaturationKey) private var light = CategoryBadgeAppearance.lightSaturation
    @AppStorage(CategoryIconDebugSettings.darkSaturationKey) private var dark = CategoryBadgeAppearance.darkSaturation

    var wrappedValue: Double {
        get { colorScheme == .dark ? dark : light }
        nonmutating set {
            if colorScheme == .dark { dark = newValue } else { light = newValue }
        }
    }

    var projectedValue: Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

@propertyWrapper
private struct CategoryDepthSettings: DynamicProperty {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CategoryIconDebugSettings.lightDepthKey) private var light = CategoryBadgeAppearance.lightDepth
    @AppStorage(CategoryIconDebugSettings.darkDepthKey) private var dark = CategoryBadgeAppearance.darkDepth

    var wrappedValue: Double {
        get { colorScheme == .dark ? dark : light }
        nonmutating set {
            if colorScheme == .dark { dark = newValue } else { light = newValue }
        }
    }

    var projectedValue: Binding<Double> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

struct CategoryIconDebugControls: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CategoryIconDebugSettings.storageKey) private var usesEmoji = false
    @CategorySaturationSettings private var saturation: Double
    @AppStorage(CategoryIconDebugSettings.foregroundKey) private var foreground = CategoryBadgeAppearance.defaultForeground
    @CategoryDepthSettings private var depth: Double

    var body: some View {
        Toggle(isOn: $usesEmoji) {
            VStack(alignment: .leading, spacing: 4) {
                Text("类别使用 Emoji")
                Text("关闭时使用 SF Symbols；编辑页、账目列表和筛选菜单同步切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.green)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(colorScheme == .dark ? "底色饱和度 · 深色" : "底色饱和度 · 浅色")
                Spacer()
                Text(saturation.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                ForEach(expenseCategories) { category in
                    ExpenseCategoryBadge(category: category, size: 34, symbolSize: 15)
                }
            }

            Slider(value: $saturation, in: 0...1.5, step: 0.01) {
                Text("底色饱和度")
            }
            .accessibilityValue(saturation.formatted(.percent.precision(.fractionLength(0))))

            HStack(alignment: .firstTextBaseline) {
                Text("浅色与深色分别保存，实时预览。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重置") {
                    saturation = colorScheme == .dark
                        ? CategoryBadgeAppearance.darkSaturation : CategoryBadgeAppearance.lightSaturation
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            Divider()

            Picker("图标前景", selection: $foreground) {
                Text("同色系深色").tag(CategoryForegroundMode.background)
                Text("自动对比").tag(CategoryForegroundMode.automatic)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("图标前景")

            HStack {
                Text("图标加深程度")
                Spacer()
                Text(depth.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $depth, in: 0...1, step: 0.01) {
                Text("图标加深程度")
            }
            .accessibilityValue(depth.formatted(.percent.precision(.fractionLength(0))))

            HStack(alignment: .firstTextBaseline) {
                Text(usesEmoji ? "前景调节仅作用于 SF Symbols，关闭 Emoji 可查看效果。"
                     : "仅调整图标本身：蓝底配深蓝图标、粉底配深粉图标，背景不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重置前景") {
                    foreground = CategoryBadgeAppearance.defaultForeground
                    depth = colorScheme == .dark ? CategoryBadgeAppearance.darkDepth : CategoryBadgeAppearance.lightDepth
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 8)
    }
}
#endif

struct CategoryBadgeBackground: DynamicProperty {
    #if DEBUG
    @CategorySaturationSettings private var saturation: Double
    @WalletPaletteSettings private var palette: WalletPalette
    #else
    @Environment(\.colorScheme) private var colorScheme
    private var saturation: Double {
        colorScheme == .dark ? CategoryBadgeAppearance.darkSaturation : CategoryBadgeAppearance.lightSaturation
    }
    #endif

    func colors(for category: ExpenseCategory) -> WalletColorPair {
        #if DEBUG
        // Resolve by ID so reordering or deleting a debug palette entry never
        // silently reassigns a category to a different color.
        let base = palette.entries.first { $0.id == category.paletteID }?.color ?? category.paletteColor
        #else
        let base = category.paletteColor
        #endif
        // Keep the palette's softer base saturation. The wallet's glass needs
        // extra saturation, but applying that boost to small badges is too vivid.
        return CategoryBadgeAppearance.colors(base: base, saturation: saturation)
    }
}

/// One palette and glyph treatment for the editor and every expense row.
struct ExpenseCategoryBadge: View {
    let category: ExpenseCategory
    let size: CGFloat
    let symbolSize: CGFloat
    private var badgeBackground = CategoryBadgeBackground()

    #if DEBUG
    @AppStorage(CategoryIconDebugSettings.storageKey) private var usesEmoji = false
    @AppStorage(CategoryIconDebugSettings.foregroundKey) private var foreground = CategoryBadgeAppearance.defaultForeground
    @CategoryDepthSettings private var depth: Double
    #else
    private let usesEmoji = false
    @Environment(\.colorScheme) private var colorScheme
    private let foreground = CategoryBadgeAppearance.defaultForeground
    private var depth: Double {
        colorScheme == .dark ? CategoryBadgeAppearance.darkDepth : CategoryBadgeAppearance.lightDepth
    }
    #endif

    var body: some View {
        let colors = badgeBackground.colors(for: category)
        let ink = CategoryBadgeAppearance.ink(for: colors, mode: foreground, depth: depth)
        Group {
            if usesEmoji {
                Text(category.emoji)
                    .font(.system(size: size * 0.56))
            } else {
                Image(systemName: category.symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(ink.color)
            }
        }
        .frame(width: size, height: size)
        .background(
            LinearGradient(colors: [colors.first.color, colors.second.color],
                           startPoint: .top, endPoint: .bottom),
            in: Circle()
        )
        .accessibilityHidden(true)
    }
}
