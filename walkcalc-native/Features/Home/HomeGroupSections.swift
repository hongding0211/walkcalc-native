import Foundation

struct HomeGroupSection: Identifiable {
    enum ID: Hashable {
        case pinned
        case month(Date)
        case year(Date)
        case undated
    }

    let id: ID
    var groups: [WalkGroup]

    func title(locale: Locale, calendar: Calendar = .autoupdatingCurrent) -> String {
        let date: Date
        let template: String
        switch id {
        case .pinned: return L("Pinned")
        case .undated: return L("Earlier")
        case .month(let value): (date, template) = (value, "MMMM")
        case .year(let value): (date, template) = (value, "y")
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func updatedDate(for group: WalkGroup) -> Date? {
        let timestamp = group.modifiedAt.isFinite && group.modifiedAt > 0 ? group.modifiedAt : group.createdAt
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp / 1_000)
    }

    static func make(groups: [WalkGroup], now: Date = Date(),
                     calendar: Calendar = .autoupdatingCurrent) -> [Self] {
        var sections: [Self] = []
        // Preserve the existing pin order supplied by the data source.
        let pinned = groups.filter(\.isPinned)
        if !pinned.isEmpty { sections.append(Self(id: .pinned, groups: pinned)) }

        let unpinned = groups.filter { !$0.isPinned }.sorted {
            let left = updatedDate(for: $0) ?? .distantPast
            let right = updatedDate(for: $1) ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
        for group in unpinned {
            let id: ID
            if let date = updatedDate(for: group) {
                if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                    id = .month(calendar.dateInterval(of: .month, for: date)!.start)
                } else {
                    id = .year(calendar.dateInterval(of: .year, for: date)!.start)
                }
            } else {
                id = .undated
            }
            if sections.last?.id == id {
                sections[sections.count - 1].groups.append(group)
            } else {
                sections.append(Self(id: id, groups: [group]))
            }
        }
        return sections
    }
}
