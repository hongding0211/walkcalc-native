#!/usr/bin/env python3
"""Exercise home grouping across updates, pagination, pins and calendar boundaries."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = r'''
import Foundation
func L(_ key: String) -> String { key }
struct WalkGroup {
    var id: String
    var modifiedAt: TimeInterval
    var createdAt: TimeInterval = 0
    var isPinned: Bool = false
}
'''
source += (root / 'walkcalc-native/Features/Home/HomeGroupSections.swift').read_text()
source += r'''
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
func group(_ id: String, _ text: String, pinned: Bool = false) -> WalkGroup {
    WalkGroup(id: id, modifiedAt: date(text).timeIntervalSince1970 * 1_000, isPinned: pinned)
}
let now = date("2026-11-15T12:00:00Z")
let newest = group("newest", "2026-11-10T12:00:00Z")
let older = group("older", "2026-11-01T12:00:00Z")
let september = group("september", "2026-09-08T12:00:00Z")
let lastYear = group("last-year", "2025-12-31T12:00:00Z")
let lastYearEarly = group("last-year-early", "2025-01-01T12:00:00Z")
let old = group("old", "2024-07-01T12:00:00Z")
let pins = [group("pin-a", "2024-01-01T12:00:00Z", pinned: true),
            group("pin-b", "2026-11-15T12:00:00Z", pinned: true)]
func sections(_ groups: [WalkGroup], at date: Date = now) -> [HomeGroupSection] {
    HomeGroupSection.make(groups: groups, now: date, calendar: calendar)
}
let input = [old, older, lastYearEarly] + pins + [september, newest, lastYear]
let result = sections(input)
precondition(result.map { $0.groups.map(\.id) } == [
    ["pin-a", "pin-b"], ["newest", "older"], ["september"], ["last-year", "last-year-early"], ["old"]
])
precondition(Set(result.flatMap(\.groups).map(\.id)).count == input.count)
precondition(result[0].id == .pinned)
let english = Locale(identifier: "en_US")
let chinese = Locale(identifier: "zh_Hans_CN")
precondition(result[1].title(locale: english, calendar: calendar) == "November")
precondition(result[1].title(locale: chinese, calendar: calendar) == "十一月")
precondition(result[3].title(locale: english, calendar: calendar) == "2025")
precondition(sections([]).isEmpty)
precondition(sections(pins).count == 1)
// The local January boundary is still December 31 in UTC.
let boundary = group("boundary", "2025-12-31T16:00:00Z")
let prior = group("prior", "2025-12-31T15:59:59Z")
let boundarySections = sections([prior, boundary], at: date("2026-01-01T00:00:00Z"))
precondition(boundarySections.count == 2)
precondition(boundarySections[0].title(locale: english, calendar: calendar) == "January")
precondition(boundarySections[1].title(locale: english, calendar: calendar) == "2025")
// Crossing New Year combines last year's month groups into one year section.
let newYear = sections([newest, september], at: date("2027-01-01T00:00:00Z"))
precondition(newYear.count == 1 && newYear[0].groups.count == 2)
// Appending a page must merge rows into an existing section.
precondition(sections([newest] + [older, september]).map { $0.groups.count } == [2, 1])
var updated = september
updated.modifiedAt = date("2026-11-15T12:00:00Z").timeIntervalSince1970 * 1_000
precondition(sections([newest, updated]).first?.groups.map(\.id) == ["september", "newest"])
var unpinned = pins[0]
unpinned.isPinned = false
precondition(sections([newest, unpinned]).last?.groups.first?.id == "pin-a")
let fallback = WalkGroup(id: "fallback", modifiedAt: 0, createdAt: newest.modifiedAt)
let unknown = WalkGroup(id: "unknown", modifiedAt: .nan)
precondition(sections([unknown, fallback]).last?.id == .undated)
precondition(HomeGroupSection.updatedDate(for: fallback) == HomeGroupSection.updatedDate(for: newest))
let tied = WalkGroup(id: "a", modifiedAt: newest.modifiedAt)
precondition(sections([newest, tied]).first?.groups.map(\.id) == ["a", "newest"])
print("PASS: month/year sections; localized headings; timezone/year rollover; update ordering; pagination merge; pin/unpin; missing dates; stable ties")
'''
with tempfile.TemporaryDirectory(prefix='walkcalc-home-sections-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', str(path / 'main.swift'), '-o', str(path / 'verify')], check=True)
    subprocess.run([str(path / 'verify')], check=True)
