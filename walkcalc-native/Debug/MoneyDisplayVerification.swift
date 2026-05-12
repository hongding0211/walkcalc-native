#if DEBUG
import Foundation

enum MoneyDisplayVerification {
    static func assertAllCasesPass() {
        expect(Money.compactDisplay("100000", localeIdentifier: "en"), equals: "1,000.00", prefix: "en-1k")
        expect(Money.compactDisplay("1000000", localeIdentifier: "en"), equals: "10,000.00", prefix: "en-10k")
        expect(Money.compactDisplay("9999999", localeIdentifier: "en"), equals: "99,999.99", prefix: "en-under-threshold")
        expect(Money.compactDisplay("10000000", localeIdentifier: "en"), equals: "100 K", prefix: "en-100k")

        expect(Money.compactDisplay("100000", localeIdentifier: "zh-Hans"), equals: "1,000.00", prefix: "zh-1k")
        expect(Money.compactDisplay("1000000", localeIdentifier: "zh-Hans"), equals: "10,000.00", prefix: "zh-10k")
        expect(Money.compactDisplay("9999999", localeIdentifier: "zh-Hans"), equals: "99,999.99", prefix: "zh-under-threshold")
        expect(Money.compactDisplay("10000000", localeIdentifier: "zh-Hans"), equals: "10 万", prefix: "zh-100k")

        expect(signedMoney("123456789012", style: .exact), equals: "+¥1,234,567,890.12", prefix: "exact-positive")
        expect(signedMoney("-123456789012", style: .exact), equals: "-¥1,234,567,890.12", prefix: "exact-negative")
        expect(signedMoney("0", style: .exact), equals: "¥0.00", prefix: "exact-zero")

        expect(Money.minorFromDecimalString("100.00"), equals: "10000", prefix: "api-decimal-positive")
        expect(Money.minorFromDecimalString("-33.33"), equals: "-3333", prefix: "api-decimal-negative")
        expect(Money.minorFromDecimalString("0.01"), equals: "1", prefix: "api-decimal-cent")
        expect(try? Money.parseDisplay("1"), equals: "100", prefix: "parse-integer")
        expect(try? Money.parseDisplay("1.2"), equals: "120", prefix: "parse-one-decimal")
        expect(try? Money.parseDisplay("1.23"), equals: "123", prefix: "parse-two-decimals")
        expect(Money.decimalString(fromMinor: "10000"), equals: "100.00", prefix: "api-request-positive")
        expect(Money.decimalString(fromMinor: "-3333"), equals: "-33.33", prefix: "api-request-negative")
        expect(Money.isPositive("1"), equals: true, prefix: "positive-cent")
        expect(Money.isPositive("0"), equals: false, prefix: "positive-zero")
        expect(Money.isPositive("-1"), equals: false, prefix: "positive-negative")
        expectInvalidDisplay("", prefix: "invalid-empty")
        expectInvalidDisplay("01.00", prefix: "invalid-leading-zero")
        expectInvalidDisplay("1.234", prefix: "invalid-three-decimals")
        expectInvalidDisplay("abc", prefix: "invalid-nonnumeric")
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }

    private static func expectInvalidDisplay(_ value: String, prefix: String) {
        do {
            _ = try Money.parseDisplay(value)
            assertionFailure("\(prefix): expected invalid display value '\(value)'")
        } catch {
        }
    }
}
#endif
