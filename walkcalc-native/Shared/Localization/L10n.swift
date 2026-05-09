import Foundation

enum L10n {
    static var preferredLanguageIdentifier: String {
        Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }

    static var serverLanguageCode: String {
        preferredLanguageIdentifier.hasPrefix("zh") ? "cn" : "en"
    }
}

func L(_ key: String) -> String {
    L10n.text(key)
}
