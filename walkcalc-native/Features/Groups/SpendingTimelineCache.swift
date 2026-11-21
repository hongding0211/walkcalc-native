import CryptoKit
import Foundation

nonisolated struct SpendingTimelineCacheKey: Hashable, Sendable {
    struct Scope: Hashable, Sendable {
        let participantID: String?
        let groupID: String
        let currencyCode: String
        let calendarID: String
        let timeZoneID: String

        var fileName: String? {
            guard let participantID, !participantID.isEmpty else { return nil }
            let components = [participantID, groupID, currencyCode, calendarID, timeZoneID]
            guard let data = try? JSONEncoder().encode(components) else { return nil }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return digest + ".json"
        }
    }

    let scope: Scope
    let modifiedAt: TimeInterval?
}

nonisolated struct SpendingTimelineSnapshot: Codable, Sendable {
    let modifiedAt: TimeInterval?
    let bounds: ClosedRange<Date>?
    var cache = TimelineCache()
}

actor SpendingTimelineDiskCache {
    static let shared = SpendingTimelineDiskCache(
        directory: URL.cachesDirectory.appending(path: "SpendingTimeline-v1", directoryHint: .isDirectory)
    )

    private let directory: URL
    private var activeRevisions: [SpendingTimelineCacheKey.Scope: TimeInterval] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func load(for key: SpendingTimelineCacheKey) -> SpendingTimelineSnapshot? {
        guard !Task.isCancelled else { return nil }
        activeRevisions[key.scope] = key.modifiedAt
        guard let revision = key.modifiedAt, let file = file(for: key) else { return nil }
        return read(file, revision: revision)
    }

    func storeBounds(_ snapshot: SpendingTimelineSnapshot, for key: SpendingTimelineCacheKey) {
        guard let (file, revision) = writableFile(for: key), read(file, revision: revision) == nil else { return }
        write(snapshot, to: file)
    }

    func store(_ points: [SpendingTimelinePoint], in interval: DateInterval,
               bounds: ClosedRange<Date>?, for key: SpendingTimelineCacheKey) {
        guard let (file, revision) = writableFile(for: key) else { return }
        var snapshot = read(file, revision: revision) ?? SpendingTimelineSnapshot(modifiedAt: revision, bounds: bounds)
        snapshot.cache.store(points, for: interval)
        write(snapshot, to: file)
    }

    private func file(for key: SpendingTimelineCacheKey) -> URL? {
        key.scope.fileName.map { directory.appending(path: $0, directoryHint: .notDirectory) }
    }

    private func writableFile(for key: SpendingTimelineCacheKey) -> (URL, TimeInterval)? {
        guard !Task.isCancelled, let revision = key.modifiedAt,
              activeRevisions[key.scope] == revision, let file = file(for: key) else { return nil }
        return (file, revision)
    }

    private func read(_ file: URL, revision: TimeInterval) -> SpendingTimelineSnapshot? {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(SpendingTimelineSnapshot.self, from: data),
              snapshot.modifiedAt == revision else { return nil }
        return snapshot
    }

    private func write(_ snapshot: SpendingTimelineSnapshot, to file: URL) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            // The chart can continue using its in-memory cache when disk storage is unavailable.
        }
    }
}

nonisolated struct TimelineCache: Codable, Sendable {
    private var pointsByDay: [Date: [SpendingTimelinePoint]] = [:]
    private var covered: [DateInterval] = []

    func points(in interval: DateInterval) -> [SpendingTimelinePoint] {
        pointsByDay.lazy.filter { $0.key >= interval.start && $0.key < interval.end }.flatMap(\.value)
    }

    func missing(in interval: DateInterval) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = interval.start
        for loaded in covered where loaded.end > cursor && loaded.start < interval.end {
            if cursor < loaded.start {
                gaps.append(DateInterval(start: cursor, end: loaded.start))
            }
            cursor = loaded.end
            if cursor >= interval.end { return gaps }
        }
        if cursor < interval.end {
            gaps.append(DateInterval(start: cursor, end: interval.end))
        }
        return gaps
    }

    mutating func store(_ points: [SpendingTimelinePoint], for interval: DateInterval) {
        pointsByDay.merge(Dictionary(grouping: points, by: \.date)) { _, new in new }
        covered.append(interval)
        let sorted = covered.sorted { $0.start < $1.start }
        covered = []
        for loaded in sorted {
            if let previous = covered.last, loaded.start <= previous.end {
                covered[covered.count - 1] = DateInterval(start: previous.start, end: max(previous.end, loaded.end))
            } else {
                covered.append(loaded)
            }
        }
    }
}
