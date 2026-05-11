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
    }

    private static func expect(_ actual: String, equals expected: String, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }
}
#endif
