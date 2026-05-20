import SwiftUI
import UIKit

struct SoftLedgerColorToken {
    let light: UInt32
    let dark: UInt32

    var color: Color {
        Color(uiColor)
    }

    var uiColor: UIColor {
        UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        }
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
    let previewAccent: UInt32
    let previewSoftAccent: UInt32
}

enum SoftLedgerThemeConfig {
    static let defaultAppTheme: AppTheme = .black

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
        case .blue:
            return AppThemePalette(
                titleKey: "Blue",
                accent: SoftLedgerColorToken(light: 0x2C6AA0, dark: 0x6EA3D0),
                accentSoft: SoftLedgerColorToken(light: 0xDCE7F1, dark: 0x1A2F40),
                previewAccent: 0x2C6AA0,
                previewSoftAccent: 0xDCE7F1
            )
        case .black:
            return AppThemePalette(
                titleKey: "Black",
                accent: SoftLedgerColorToken(light: 0x18181B, dark: 0xFAFAFA),
                accentSoft: SoftLedgerColorToken(light: 0xF4F4F5, dark: 0x27272A),
                previewAccent: 0x18181B,
                previewSoftAccent: 0xF4F4F5
            )
        case .yellow:
            return AppThemePalette(
                titleKey: "Yellow",
                accent: yellowAccent,
                accentSoft: SoftLedgerColorToken(light: 0xEDCBA4, dark: 0x38322F),
                previewAccent: 0xB15525,
                previewSoftAccent: 0xEDCBA4
            )
        case .green:
            return AppThemePalette(
                titleKey: "Green",
                accent: SoftLedgerColorToken(light: 0x1D6F50, dark: 0x6FBC8D),
                accentSoft: SoftLedgerColorToken(light: 0xDCEBE3, dark: 0x1A3327),
                previewAccent: 0x1D6F50,
                previewSoftAccent: 0xDCEBE3
            )
        }
    }
}
