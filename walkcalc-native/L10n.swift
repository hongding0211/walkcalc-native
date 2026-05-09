import Foundation

enum L10n {
    static var isChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    static func text(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}

func L(_ zh: String, _ en: String) -> String {
    L10n.text(zh, en)
}
