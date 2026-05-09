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

extension Decimal {
    static prefix func - (value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalMultiplyByPowerOf10(&result, &input, 0, .plain)
        return result * Decimal(-1)
    }
}
