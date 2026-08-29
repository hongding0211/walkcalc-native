import SwiftUI
import UIKit

struct SoftLedgerColorToken {
    let uiColor: UIColor

    init(light: UInt32, dark: UInt32) {
        uiColor = UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        }
    }

    init(systemColor: UIColor) {
        uiColor = systemColor
    }

    var color: Color {
        Color(uiColor)
    }
}

struct SoftLedgerNeutralPalette {
    let canvas: SoftLedgerColorToken
    let paper: SoftLedgerColorToken
    let formPaper: SoftLedgerColorToken
    let defaultText: SoftLedgerColorToken
    let secondaryText: SoftLedgerColorToken
    let mutedText: SoftLedgerColorToken
    let rule: SoftLedgerColorToken
    let positive: SoftLedgerColorToken
    let negative: SoftLedgerColorToken
}

struct AppThemePalette {
    let titleKey: String
    let accent: SoftLedgerColorToken
    let accentSoft: SoftLedgerColorToken
}

enum SoftLedgerThemeConfig {
    static let defaultAppTheme: AppTheme = .mono

    static let neutral = SoftLedgerNeutralPalette(
        canvas: SoftLedgerColorToken(light: 0xF7F7F7, dark: 0x000000),
        paper: SoftLedgerColorToken(light: 0xFFFFFF, dark: 0x141414),
        formPaper: SoftLedgerColorToken(light: 0xFFFFFF, dark: 0x1C1C1C),
        defaultText: SoftLedgerColorToken(light: 0x1C1C1C, dark: 0xF2F2F2),
        secondaryText: SoftLedgerColorToken(light: 0x666666, dark: 0xC7C7C7),
        mutedText: SoftLedgerColorToken(light: 0x8A8A8A, dark: 0x8E8E8E),
        rule: SoftLedgerColorToken(light: 0xD9D9D9, dark: 0x3A3A3A),
        positive: SoftLedgerColorToken(light: 0x167454, dark: 0x77C99E),
        negative: SoftLedgerColorToken(light: 0xAC2F24, dark: 0xF07C6C)
    )

    static let yellowAccent = SoftLedgerColorToken(light: 0xB15525, dark: 0xE49B63)

    static func palette(for theme: AppTheme) -> AppThemePalette {
        switch theme {
        case .mono:
            return AppThemePalette(
                titleKey: "Mono",
                accent: SoftLedgerColorToken(systemColor: .label),
                accentSoft: SoftLedgerColorToken(light: 0xF4F4F5, dark: 0x27272A)
            )
        case .blue:
            return AppThemePalette(
                titleKey: "Blue",
                accent: SoftLedgerColorToken(systemColor: .systemBlue),
                accentSoft: SoftLedgerColorToken(systemColor: UIColor.systemBlue.withAlphaComponent(0.16))
            )
        case .pink:
            return AppThemePalette(
                titleKey: "Pink",
                accent: SoftLedgerColorToken(systemColor: .systemPink),
                accentSoft: SoftLedgerColorToken(systemColor: UIColor.systemPink.withAlphaComponent(0.16))
            )
        case .yellow:
            return AppThemePalette(
                titleKey: "Yellow",
                accent: SoftLedgerColorToken(systemColor: .systemYellow),
                accentSoft: SoftLedgerColorToken(systemColor: UIColor.systemYellow.withAlphaComponent(0.16))
            )
        case .green:
            return AppThemePalette(
                titleKey: "Green",
                accent: SoftLedgerColorToken(systemColor: .systemGreen),
                accentSoft: SoftLedgerColorToken(systemColor: UIColor.systemGreen.withAlphaComponent(0.16))
            )
        }
    }
}
