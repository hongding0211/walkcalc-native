#if DEBUG
import SwiftUI
import Observation
import UIKit

struct MoneyDebugPalette: Codable {
    var positiveLight = WalletRGB(hex: SoftLedgerThemeConfig.positiveLight)
    var positiveDark = WalletRGB(hex: SoftLedgerThemeConfig.positiveDark)
    var negativeLight = WalletRGB(hex: SoftLedgerThemeConfig.negativeLight)
    var negativeDark = WalletRGB(hex: SoftLedgerThemeConfig.negativeDark)
}

@Observable
final class DebugMoneyColors {
    static let shared = DebugMoneyColors()
    // Restore the original approved colors instead of reviving trial overrides.
    private static let storageKey = "debug.moneyColors.v2"

    var palette: MoneyDebugPalette {
        didSet {
            if let data = try? JSONEncoder().encode(palette) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    private init() {
        palette = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(MoneyDebugPalette.self, from: $0) } ?? MoneyDebugPalette()
    }

    var positive: Color { adaptive(light: palette.positiveLight, dark: palette.positiveDark) }
    var negative: Color { adaptive(light: palette.negativeLight, dark: palette.negativeDark) }

    private func adaptive(light: WalletRGB, dark: WalletRGB) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}

struct MoneyColorDebugControls: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var colors = DebugMoneyColors.shared

    private var positivePath: WritableKeyPath<MoneyDebugPalette, WalletRGB> {
        colorScheme == .dark ? \.positiveDark : \.positiveLight
    }
    private var negativePath: WritableKeyPath<MoneyDebugPalette, WalletRGB> {
        colorScheme == .dark ? \.negativeDark : \.negativeLight
    }

    var body: some View {
        HStack {
            Text("+¥128.00").foregroundStyle(SoftLedgerTheme.positive)
            Spacer()
            Text("−¥128.00").foregroundStyle(SoftLedgerTheme.negative)
        }
        .font(.title2.weight(.semibold).monospacedDigit())
        .padding(.vertical, 8)

        ColorPicker("正数颜色（绿）", selection: binding(positivePath), supportsOpacity: false)
        ColorPicker("负数颜色（红）", selection: binding(negativePath), supportsOpacity: false)

        Button("重置当前模式的金额颜色") {
            let defaults = MoneyDebugPalette()
            colors.palette[keyPath: positivePath] = defaults[keyPath: positivePath]
            colors.palette[keyPath: negativePath] = defaults[keyPath: negativePath]
        }
    }

    private func binding(_ path: WritableKeyPath<MoneyDebugPalette, WalletRGB>) -> Binding<Color> {
        Binding(get: { colors.palette[keyPath: path].color }, set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            colors.palette[keyPath: path] = WalletRGB(red: red, green: green, blue: blue)
        })
    }
}
#endif
