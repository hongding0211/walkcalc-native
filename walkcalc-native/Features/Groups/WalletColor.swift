import Foundation

enum WalletInkMode: String, Codable, CaseIterable, Identifiable {
    case automatic, dark, light, custom
    var id: Self { self }
}

// Explicit sRGB components do not change with the system appearance.
struct WalletRGB: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let black = Self(hex: 0x000000)
    static let white = Self(hex: 0xFFFFFF)

    init(hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((Self.clamp(red) * 255).rounded()),
               Int((Self.clamp(green) * 255).rounded()), Int((Self.clamp(blue) * 255).rounded()))
    }

    func mixed(with other: Self, amount: Double) -> Self {
        let t = Self.clamp(amount)
        return Self(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                    blue: blue + (other.blue - blue) * t)
    }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let high = max(red, green, blue), low = min(red, green, blue)
        let delta = high - low
        guard delta > 0 else { return (0, 0, high) }
        let h: Double
        if high == red { h = (green - blue) / delta }
        else if high == green { h = (blue - red) / delta + 2 }
        else { h = (red - green) / delta + 4 }
        return ((h / 6 + 1).truncatingRemainder(dividingBy: 1), delta / high, high)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = ((hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)) * 6
        let s = Self.clamp(saturation), v = Self.clamp(brightness)
        let f = h - floor(h), p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let rgb: (Double, Double, Double)
        switch Int(h) % 6 {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        self.init(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    func adjusted(saturation: Double, brightness: Double, hue: Double) -> Self {
        let values = hsb
        return Self(hue: values.hue + hue / 360, saturation: values.saturation * saturation,
                    brightness: values.brightness + brightness)
    }

    private var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: Self) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

struct WalletColorPair: Codable, Equatable {
    var first: WalletRGB
    var second: WalletRGB

    // Shared by Release rendering and the Debug palette editor, including order.
    static let defaultPalette: [(id: String, hex: UInt32)] = [
        ("cornflower", 0xA4BAEA),
        ("pistachio", 0xC1D99B),
        ("rose", 0xEAB0C5),
        ("cream", 0xEAD59A),
        ("sky", 0x93D8EF),
        ("mint", 0x9DD7C8),
        ("iris", 0xB9AFEA),
        ("apricot", 0xF2BD9E)
    ]

    static let defaults = defaultPalette.map { entry in
        let color = WalletRGB(hex: entry.hex)
        return Self(first: color, second: color)
    }

    func ink(mode: WalletInkMode, custom: WalletRGB) -> WalletRGB {
        switch mode {
        case .dark: return WalletRGB(hex: 0x141927)
        case .light: return .white
        case .custom: return custom
        case .automatic:
            let hue = first.mixed(with: second, amount: 0.5).hsb.hue
            let candidates = [WalletRGB(hue: hue, saturation: 0.45, brightness: 0.23),
                              WalletRGB(hue: hue, saturation: 0.08, brightness: 0.98)]
            func score(_ ink: WalletRGB) -> Double {
                (0...10).map { ink.contrast(with: first.mixed(with: second, amount: Double($0) / 10)) }.min() ?? 1
            }
            let matched = candidates.max { score($0) < score($1) }!
            if score(matched) >= 4.5 { return matched }
            return [WalletRGB.black, .white].max { score($0) < score($1) }!
        }
    }
}
