import Foundation

enum TemporalDisplayContext {
    case dense
    case compact
    case full
}

enum TemporalDisplayBucket {
    case today
    case yesterday
    case currentWeek
    case currentYear
    case previousYear
}

enum TemporalDisplay {
    static func string(
        from date: Date,
        context: TemporalDisplayContext,
        now: Date = Date(),
        locale: Locale = appLocale,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let bucket = bucket(for: date, now: now, calendar: calendar)
        let language = TemporalDisplayLanguage(locale: locale)
        let time = language.timeString(from: date, calendar: calendar)

        switch bucket {
        case .today:
            return time
        case .yesterday:
            return "\(language.yesterday(context: context)) \(time)"
        case .currentWeek:
            return "\(language.weekdayString(from: date, calendar: calendar)) \(time)"
        case .currentYear:
            let dateText = language.monthDayString(from: date, calendar: calendar)
            return context == .full ? language.dateTimeString(dateText: dateText, timeText: time) : dateText
        case .previousYear:
            let dateText = language.yearMonthDayString(from: date, calendar: calendar)
            return context == .full ? language.dateTimeString(dateText: dateText, timeText: time) : dateText
        }
    }

    static func string(
        fromMilliseconds milliseconds: TimeInterval,
        context: TemporalDisplayContext,
        now: Date = Date(),
        locale: Locale = appLocale,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        string(
            from: milliseconds.walkDate,
            context: context,
            now: now,
            locale: locale,
            calendar: calendar
        )
    }

    static func bucket(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> TemporalDisplayBucket {
        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }

        if let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
           currentWeek.contains(date) {
            return .currentWeek
        }

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return .currentYear
        }

        return .previousYear
    }

    private static var appLocale: Locale {
        let identifier = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale(identifier: identifier)
    }
}

private struct TemporalDisplayLanguage {
    let locale: Locale
    let isChinese: Bool

    init(locale: Locale) {
        self.locale = locale
        isChinese = locale.identifier.lowercased().hasPrefix("zh")
    }

    func yesterday(context: TemporalDisplayContext) -> String {
        if isChinese {
            return "昨天"
        }

        return context == .dense ? "Yest" : "Yesterday"
    }

    func weekdayString(from date: Date, calendar: Calendar) -> String {
        if isChinese {
            let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return weekdays[calendar.component(.weekday, from: date) - 1]
        }

        return formatted(date, format: "EEE", locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
    }

    func timeString(from date: Date, calendar: Calendar) -> String {
        formatted(date, format: "HH:mm", locale: formatterLocale, calendar: calendar)
    }

    func monthDayString(from date: Date, calendar: Calendar) -> String {
        formatted(date, format: isChinese ? "M月d日" : "MMM d", locale: formatterLocale, calendar: calendar)
    }

    func yearMonthDayString(from date: Date, calendar: Calendar) -> String {
        formatted(date, format: isChinese ? "yyyy年M月d日" : "MMM d, yyyy", locale: formatterLocale, calendar: calendar)
    }

    func dateTimeString(dateText: String, timeText: String) -> String {
        isChinese ? "\(dateText) \(timeText)" : "\(dateText), \(timeText)"
    }

    private var formatterLocale: Locale {
        isChinese ? Locale(identifier: "zh_Hans_CN") : Locale(identifier: "en_US_POSIX")
    }

    private func formatted(_ date: Date, format: String, locale: Locale, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
