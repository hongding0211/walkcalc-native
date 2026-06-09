import Foundation

typealias MoneyMinor = String

private let maxAbsMinor = Decimal(999_999_999_999_999_999)

enum Money {
    static func parseDisplay(_ value: String) throws -> MoneyMinor {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^-?(?:0|[1-9]\d*)(?:\.\d{1,2})?$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw MoneyError.invalid
        }

        let negative = trimmed.hasPrefix("-")
        let unsigned = negative ? String(trimmed.dropFirst()) : trimmed
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let integerPart = Decimal(string: String(parts.first ?? "0")) ?? 0
        let fractionRaw = parts.count > 1 ? String(parts[1]) : ""
        let fraction = Decimal(string: fractionRaw.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        var minor = integerPart * 100 + fraction
        if negative {
            minor *= -1
        }
        guard abs(minor) <= maxAbsMinor else {
            throw MoneyError.outOfRange
        }
        return NSDecimalNumber(decimal: minor).stringValue
    }

    static func normalize(_ value: Any?) -> MoneyMinor {
        if let string = value as? String, isValidMinor(string) {
            return NSDecimalNumber(string: string).stringValue
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let double = value as? Double, double.isFinite {
            return "\(Int(double.rounded()))"
        }
        return "0"
    }

    static func minorFromDecimalString(_ value: Any?) -> MoneyMinor {
        guard let string = value as? String,
              let minor = try? parseDisplay(string) else {
            return "0"
        }
        return minor
    }

    static func decimalString(fromMinor value: MoneyMinor) -> String {
        let minor = NSDecimalNumber(decimal: decimal(value)).int64Value
        let negative = minor < 0
        let absValue = Swift.abs(minor)
        let integer = absValue / 100
        let fraction = absValue % 100
        return "\(negative ? "-" : "")\(integer).\(String(format: "%02d", fraction))"
    }

    static func decimal(_ value: MoneyMinor?) -> Decimal {
        Decimal(string: value ?? "0") ?? 0
    }

    static func add(_ left: MoneyMinor, _ right: MoneyMinor) -> MoneyMinor {
        formatRaw(decimal(left) + decimal(right))
    }

    static func negate(_ value: MoneyMinor) -> MoneyMinor {
        formatRaw(-decimal(value))
    }

    static func compare(_ left: MoneyMinor, _ right: MoneyMinor) -> ComparisonResult {
        let lhs = decimal(left)
        let rhs = decimal(right)
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    static func isNegative(_ value: MoneyMinor?) -> Bool {
        decimal(value) < 0
    }

    static func isZero(_ value: MoneyMinor?) -> Bool {
        decimal(value) == 0
    }

    static func isPositive(_ value: MoneyMinor?) -> Bool {
        decimal(value) > 0
    }

    static func splitFirst(_ value: MoneyMinor?, count: Int) -> MoneyMinor {
        guard count > 0 else { return "0" }
        let total = NSDecimalNumber(decimal: decimal(value)).int64Value
        let base = total / Int64(count)
        let remainder = total % Int64(count)
        if remainder == 0 {
            return "\(base)"
        }
        return "\(base + (remainder > 0 ? 1 : -1))"
    }

    static func display(_ value: MoneyMinor?) -> String {
        let minor = NSDecimalNumber(decimal: decimal(value)).int64Value
        let negative = minor < 0
        let absValue = Swift.abs(minor)
        let integer = absValue / 100
        let fraction = absValue % 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let integerString = formatter.string(from: NSNumber(value: integer)) ?? "\(integer)"
        return "\(negative ? "-" : "")\(integerString).\(String(format: "%02d", fraction))"
    }

    static func editableDisplay(_ value: MoneyMinor?) -> String {
        let minor = NSDecimalNumber(decimal: decimal(value)).int64Value
        let negative = minor < 0
        let absValue = Swift.abs(minor)
        let integer = absValue / 100
        let fraction = absValue % 100
        return "\(negative ? "-" : "")\(integer).\(String(format: "%02d", fraction))"
    }

    static func compactDisplay(_ value: MoneyMinor?, localeIdentifier: String = L10n.preferredLanguageIdentifier) -> String {
        let amount = NSDecimalNumber(decimal: decimal(value) / 100).doubleValue
        let negative = amount < 0
        let absAmount = Swift.abs(amount)
        let usesChineseUnits = localeIdentifier.hasPrefix("zh")
        let scales: [(threshold: Double, divisor: Double, suffix: String)] = usesChineseUnits
            ? [(100_000_000, 100_000_000, "亿"), (100_000, 10_000, "万")]
            : [(1_000_000_000, 1_000_000_000, "B"), (1_000_000, 1_000_000, "M"), (100_000, 1_000, "K")]

        guard let scale = scales.first(where: { absAmount >= $0.threshold }) else {
            return display(value)
        }

        let scaled = absAmount / scale.divisor
        let formatted = compactNumberString(scaled)
        let separator = " "
        return "\(negative ? "-" : "")\(formatted)\(separator)\(scale.suffix)"
    }

    private static func compactNumberString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value < 10 ? 1 : 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func isValidMinor(_ value: String) -> Bool {
        value.range(of: #"^-?(0|[1-9]\d*)$"#, options: .regularExpression) != nil
    }

    private static func formatRaw(_ value: Decimal) -> MoneyMinor {
        NSDecimalNumber(decimal: value).stringValue
    }
}

enum MoneyError: Error {
    case invalid
    case outOfRange
}

struct CurrencyInfo: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let symbol: String

    var displayTitle: String {
        "\(code) - \(name)"
    }

    var primaryListText: String {
        symbol.isEmpty || symbol == code ? name : "\(name) (\(symbol))"
    }
}

enum CurrencyCatalog {
    static let fallbackCode = "CNY"

    private static let supportedCodes = [
        "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
        "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BRL",
        "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHF", "CLP", "CNY",
        "COP", "CRC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD", "EGP",
        "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL", "GHS", "GIP", "GMD",
        "GNF", "GTQ", "GYD", "HKD", "HNL", "HTG", "HUF", "IDR", "ILS", "INR",
        "IQD", "IRR", "ISK", "JMD", "JOD", "JPY", "KES", "KGS", "KHR", "KMF",
        "KPW", "KRW", "KWD", "KYD", "KZT", "LAK", "LBP", "LKR", "LRD", "LSL",
        "LYD", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP", "MRU", "MUR",
        "MVR", "MWK", "MXN", "MYR", "MZN", "NAD", "NGN", "NIO", "NOK", "NPR",
        "NZD", "OMR", "PAB", "PEN", "PGK", "PHP", "PKR", "PLN", "PYG", "QAR",
        "RON", "RSD", "RUB", "RWF", "SAR", "SBD", "SCR", "SDG", "SEK", "SGD",
        "SHP", "SLE", "SOS", "SRD", "SSP", "STN", "SYP", "SZL", "THB", "TJS",
        "TMT", "TND", "TOP", "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD",
        "UYU", "UZS", "VES", "VND", "VUV", "WST", "XAF", "XCD", "XOF", "XPF",
        "YER", "ZAR", "ZMW", "ZWL"
    ]

    static var currencies: [CurrencyInfo] {
        supportedCodes.map { code in
            currencyInfo(code)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func normalizedCode(_ code: String?) -> String {
        let normalized = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let normalized,
              supportedCodes.contains(normalized) else {
            return defaultCurrencyCode()
        }
        return normalized
    }

    static func defaultCurrencyCode(locale: Locale = .current) -> String {
        if #available(iOS 16, *), let code = locale.currency?.identifier {
            return supportedCodes.contains(code) ? code : fallbackCode
        }
        let regionCode: String?
        if #available(iOS 16, *) {
            regionCode = locale.region?.identifier
        } else {
            regionCode = locale.regionCode
        }
        guard let regionCode else { return fallbackCode }
        return regionCurrencyCode(regionCode) ?? fallbackCode
    }

    static func currencyInfo(for code: String?) -> CurrencyInfo {
        currencyInfo(normalizedCode(code))
    }

    static func symbol(for code: String?) -> String {
        currencyInfo(for: code).symbol
    }

    static func formatted(_ value: MoneyMinor?, currencyCode: String?, style: MoneyDisplayStyle = .compact, signed: Bool = false) -> String {
        let code = normalizedCode(currencyCode)
        let amount = style.string(value)
        let prefix: String
        if signed {
            if Money.isPositive(value) {
                prefix = "+"
            } else if Money.isNegative(value) {
                prefix = "-"
            } else {
                prefix = ""
            }
        } else {
            prefix = Money.isNegative(value) ? "-" : ""
        }
        let unsignedAmount = amount.hasPrefix("-") ? String(amount.dropFirst()) : amount
        return "\(prefix)\(symbol(for: code))\(unsignedAmount)"
    }

    static func matches(_ currency: CurrencyInfo, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return currency.code.lowercased().contains(normalized)
            || currency.name.lowercased().contains(normalized)
            || currency.symbol.lowercased().contains(normalized)
    }

    private static func currencyInfo(_ code: String) -> CurrencyInfo {
        let locale = Locale.current
        let name = locale.localizedString(forCurrencyCode: code) ?? code
        let symbol = currencySymbol(code: code, locale: locale)
        return CurrencyInfo(code: code, name: name, symbol: symbol)
    }

    private static func currencySymbol(code: String, locale: Locale) -> String {
        if let symbol = explicitSymbol(for: code) {
            return symbol
        }
        if let localeSymbol = symbolFromMatchingLocale(code: code) {
            return localeSymbol
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: 0) ?? "\(code)0.00"
        let stripped = formatted
            .replacingOccurrences(of: "0", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? code : stripped
    }

    private static func symbolFromMatchingLocale(code: String) -> String? {
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            let localeCurrencyCode: String?
            if #available(iOS 16, *) {
                localeCurrencyCode = locale.currency?.identifier
            } else {
                localeCurrencyCode = locale.currencyCode
            }
            guard localeCurrencyCode == code,
                  let symbol = locale.currencySymbol,
                  !symbol.isEmpty,
                  symbol != code else {
                continue
            }
            return symbol
        }
        return nil
    }

    private static func explicitSymbol(for code: String) -> String? {
        switch code {
        case "CNY", "JPY":
            return "¥"
        case "USD":
            return "$"
        case "EUR":
            return "€"
        case "GBP":
            return "£"
        case "HKD":
            return "HK$"
        case "TWD":
            return "NT$"
        default:
            return nil
        }
    }

    private static func regionCurrencyCode(_ regionCode: String) -> String? {
        switch regionCode.uppercased() {
        case "CN": return "CNY"
        case "US": return "USD"
        case "HK": return "HKD"
        case "MO": return "MOP"
        case "TW": return "TWD"
        case "JP": return "JPY"
        case "KR": return "KRW"
        case "GB": return "GBP"
        case "AU": return "AUD"
        case "CA": return "CAD"
        case "SG": return "SGD"
        case "NZ": return "NZD"
        default: return nil
        }
    }
}

extension Decimal {
    static prefix func - (value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalMultiplyByPowerOf10(&result, &input, 0, .plain)
        return result * Decimal(-1)
    }
}
