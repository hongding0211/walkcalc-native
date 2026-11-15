import Foundation

enum CategoryForegroundMode: String, CaseIterable {
    case background
    case automatic
}

enum CategoryBadgeAppearance {
    static let lightSaturation = 0.70
    static let darkSaturation = 1.00
    static let lightDepth = 0.80
    static let darkDepth = 1.00
    static let defaultForeground: CategoryForegroundMode = .background

    static func colors(base: WalletRGB, saturation: Double) -> WalletColorPair {
        WalletColorPair(
            first: base.mixed(with: .white, amount: 0.16)
                .adjusted(saturation: saturation, brightness: 0, hue: 0),
            second: base.adjusted(saturation: 1.10 * saturation, brightness: -0.035, hue: 0)
        )
    }

    static func ink(for colors: WalletColorPair, mode: CategoryForegroundMode, depth: Double) -> WalletRGB {
        let depth = min(1, max(0, depth))
        let automatic = colors.ink(mode: .automatic, custom: .black)
        let ink: WalletRGB
        if mode == .background {
            let fill = colors.first.mixed(with: colors.second, amount: 0.5).hsb
            // Preserve the hue and strengthen chroma before reducing brightness.
            // Mixing a pastel with mostly black makes every glyph look charcoal.
            let saturation = fill.saturation < 0.025 ? 0 : max(0.72, min(0.90, fill.saturation * 1.5))
            var candidate = WalletRGB(hue: fill.hue, saturation: saturation, brightness: 0.55)
            // Darken within the same hue if a custom fill needs more contrast.
            for _ in 0..<16 {
                if minimumContrast(candidate, on: colors) >= 4.5 {
                    // Apply depth after finding the readable baseline so moving
                    // the slider right always makes the same glyph darker.
                    let deeper = candidate.adjusted(saturation: 1,
                        brightness: -candidate.hsb.brightness * depth * 0.45, hue: 0)
                    return minimumContrast(deeper, on: colors) >= 4.5 ? deeper : automatic
                }
                candidate = candidate.adjusted(saturation: 1, brightness: -0.025, hue: 0)
            }
            ink = candidate
        } else {
            ink = automatic.mixed(with: .black, amount: depth * 0.75)
        }
        // Custom dark palettes may need light ink. Preserve legibility across
        // the full gradient instead of forcing a dark symbol on a dark fill.
        return minimumContrast(ink, on: colors) >= 4.5 ? ink : automatic
    }

    private static func minimumContrast(_ ink: WalletRGB, on colors: WalletColorPair) -> Double {
        (0...10).map {
            ink.contrast(with: colors.first.mixed(with: colors.second, amount: Double($0) / 10))
        }.min() ?? 1
    }
}
