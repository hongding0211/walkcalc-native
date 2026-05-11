import Foundation

#if DEBUG
enum TemporalDisplayVerification {
    struct Result: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let expected: String
        let actual: String

        var passed: Bool {
            expected == actual
        }
    }

    static func run() -> [Result] {
        let calendar = verificationCalendar
        let now = date(year: 2026, month: 5, day: 15, hour: 16, minute: 30, calendar: calendar)

        let samples: [(name: String, date: Date)] = [
            ("today", date(year: 2026, month: 5, day: 15, hour: 14, minute: 5, calendar: calendar)),
            ("yesterday", date(year: 2026, month: 5, day: 14, hour: 14, minute: 5, calendar: calendar)),
            ("currentWeek", date(year: 2026, month: 5, day: 11, hour: 14, minute: 5, calendar: calendar)),
            ("currentYear", date(year: 2026, month: 5, day: 8, hour: 14, minute: 5, calendar: calendar)),
            ("previousYear", date(year: 2025, month: 5, day: 8, hour: 14, minute: 5, calendar: calendar))
        ]

        let zhFull = ["14:05", "昨天 14:05", "周一 14:05", "5月8日 14:05", "2025年5月8日 14:05"]
        let zhCompact = ["14:05", "昨天 14:05", "周一 14:05", "5月8日", "2025年5月8日"]
        let zhDense = zhCompact
        let enFull = ["14:05", "Yesterday 14:05", "Mon 14:05", "May 8, 14:05", "May 8, 2025, 14:05"]
        let enCompact = ["14:05", "Yesterday 14:05", "Mon 14:05", "May 8", "May 8, 2025"]
        let enDense = ["14:05", "Yest 14:05", "Mon 14:05", "May 8", "May 8, 2025"]

        return results(
            prefix: "zh-full",
            samples: samples,
            expected: zhFull,
            context: .full,
            now: now,
            locale: Locale(identifier: "zh-Hans"),
            calendar: calendar
        ) + results(
            prefix: "zh-compact",
            samples: samples,
            expected: zhCompact,
            context: .compact,
            now: now,
            locale: Locale(identifier: "zh-Hans"),
            calendar: calendar
        ) + results(
            prefix: "zh-dense",
            samples: samples,
            expected: zhDense,
            context: .dense,
            now: now,
            locale: Locale(identifier: "zh-Hans"),
            calendar: calendar
        ) + results(
            prefix: "en-full",
            samples: samples,
            expected: enFull,
            context: .full,
            now: now,
            locale: Locale(identifier: "en"),
            calendar: calendar
        ) + results(
            prefix: "en-compact",
            samples: samples,
            expected: enCompact,
            context: .compact,
            now: now,
            locale: Locale(identifier: "en"),
            calendar: calendar
        ) + results(
            prefix: "en-dense",
            samples: samples,
            expected: enDense,
            context: .dense,
            now: now,
            locale: Locale(identifier: "en"),
            calendar: calendar
        )
    }

    static func assertAllCasesPass() {
        let failures = run().filter { !$0.passed }
        assert(failures.isEmpty, failures.map { "\($0.name): expected \($0.expected), got \($0.actual)" }.joined(separator: "\n"))
    }

    private static var verificationCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    private static func results(
        prefix: String,
        samples: [(name: String, date: Date)],
        expected: [String],
        context: TemporalDisplayContext,
        now: Date,
        locale: Locale,
        calendar: Calendar
    ) -> [Result] {
        zip(samples, expected).map { sample, expected in
            Result(
                name: "\(prefix)-\(sample.name)",
                expected: expected,
                actual: TemporalDisplay.string(
                    from: sample.date,
                    context: context,
                    now: now,
                    locale: locale,
                    calendar: calendar
                )
            )
        }
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date ?? Date(timeIntervalSince1970: 0)
    }
}
#endif
