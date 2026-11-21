import Foundation
import SwiftUI
import UIKit

struct APIEnvelope<T> {
    var success: Bool
    var data: T?
    var pagination: Pagination?
    var message: String?
    var errorData: [String: Any]?
    var refreshedToken: String?
    var statusCode: Int?
    var failureKind: APIFailureKind?
}

enum APIFailureKind: String {
    case transport
    case cancellation
    case requestEncoding
    case httpStatus
    case serverEnvelope
    case authRefresh
}

struct APIClientError: Error {
    var kind: APIFailureKind
    var statusCode: Int?
    var message: String?
}

struct Pagination: Equatable {
    var page: Int
    var size: Int
    var total: Int
}

struct UserProfile: Identifiable, Hashable, Codable {
    var id: String { uuid }
    var uuid: String
    var name: String
    var avatar: String
}

struct LoginSession {
    var accessToken: String
    var refreshToken: String?
    var user: UserProfile?
}

struct Member: Identifiable, Hashable {
    var id: String { uuid }
    var uuid: String
    var name: String
    var avatar: String
    var debtMinor: MoneyMinor
    var costMinor: MoneyMinor
    var recordCount: Int = 0
    var isTemporary: Bool = false
    var currencyBalances: [MemberCurrencyProjection] = []

    var hasUnresolvedCurrencyBalance: Bool {
        if !currencyBalances.isEmpty {
            return currencyBalances.contains { !Money.isZero($0.debtMinor) }
        }
        return !Money.isZero(debtMinor)
    }
}

struct MemberCurrencyProjection: Identifiable, Hashable, Codable {
    var id: String { currencyCode }
    var currencyCode: String
    var debtMinor: MoneyMinor
    var costMinor: MoneyMinor
    var paidTotalMinor: MoneyMinor
    var recordCount: Int
    var settlementInMinor: MoneyMinor
    var settlementOutMinor: MoneyMinor

    var hasLedgerActivity: Bool {
        recordCount > 0
            || !Money.isZero(debtMinor)
            || !Money.isZero(costMinor)
            || !Money.isZero(paidTotalMinor)
            || !Money.isZero(settlementInMinor)
            || !Money.isZero(settlementOutMinor)
    }
}

struct GroupPinState {
    var pinnedAt: TimeInterval?
}

struct WalkGroup: Identifiable, Hashable {
    var id: String
    var name: String
    var currencyCode: String = CurrencyCatalog.defaultCurrencyCode()
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval
    var membersInfo: [Member]
    var tempUsers: [Member]
    var archivedUsers: [String]
    var ownerUserId: String? = nil
    var isOwner: Bool
    var hasCurrentUserBalanceSummary: Bool = false
    var currentUserBalanceMinor: MoneyMinor = "0"
    var currentUserExpenseShareMinor: MoneyMinor = "0"
    var currentUserPaidTotalMinor: MoneyMinor = "0"
    var currentUserRecordCount: Int = 0
    var currentUserCurrencyBalances: [MemberCurrencyProjection] = []
    var participantCount: Int = 0
    var participantPreview: [Member] = []
    var historicalMembers: [Member] = []
    var serverHasUnresolvedBalance: Bool?
    var pinnedAt: TimeInterval? = nil

    var isPinned: Bool { pinnedAt != nil }

    /// Used by local ledgers and to merge local rows without reordering server rows.
    static func homePrecedes(_ lhs: WalkGroup, _ rhs: WalkGroup) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if let left = lhs.pinnedAt, let right = rhs.pinnedAt, left != right { return left < right }
        if lhs.isPinned { return lhs.id < rhs.id }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.id < rhs.id
    }

    static func mergingLocalGroups(_ local: [WalkGroup], into remote: [WalkGroup]) -> [WalkGroup] {
        var result = remote
        for group in local.sorted(by: homePrecedes) {
            let index = result.firstIndex { homePrecedes(group, $0) } ?? result.endIndex
            result.insert(group, at: index)
        }
        return result
    }

    var allMembers: [Member] {
        membersInfo + tempUsers
    }

    mutating func reconcileParticipantPreview(with members: [Member]) {
        guard !participantPreview.isEmpty else { return }
        let membersByID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let previewIDs = Set(participantPreview.map(\.id))
        let retained = participantPreview.compactMap { membersByID[$0.id] }
        let remaining = members.filter { !previewIDs.contains($0.id) }
        participantPreview = Array((retained + remaining).prefix(max(3, participantPreview.count)))
    }

    var recordMembers: [Member] {
        allMembers + historicalMembers
    }

    var ownerMember: Member? {
        guard let ownerUserId else { return nil }
        return allMembers.first { $0.uuid == ownerUserId }
            ?? participantPreview.first { $0.uuid == ownerUserId }
    }

    var canCurrentUserDelete: Bool {
        isOwner
    }

    var hasUnresolvedBalance: Bool {
        if let serverHasUnresolvedBalance {
            return serverHasUnresolvedBalance
        }
        if !allMembers.isEmpty {
            return allMembers.contains { $0.hasUnresolvedCurrencyBalance }
        }
        if !currentUserCurrencyBalances.isEmpty {
            return currentUserCurrencyBalances.contains { !Money.isZero($0.debtMinor) }
        }
        return !Money.isZero(currentUserBalanceMinor)
    }

    var shouldShowDeleteResolutionNotice: Bool {
        if let serverHasUnresolvedBalance {
            return serverHasUnresolvedBalance
        }
        if allMembers.isEmpty {
            return participantCount > 1 || hasUnresolvedBalance
        }
        return hasUnresolvedBalance
    }

    var shouldBlockArchive: Bool {
        if let serverHasUnresolvedBalance {
            return serverHasUnresolvedBalance
        }
        if allMembers.isEmpty {
            return hasUnresolvedBalance
        }
        return hasUnresolvedBalance
    }
}

struct WalkRecord: Identifiable, Hashable {
    static let automaticSettlementNote = "Settlement"

    var id: String { recordId }
    var recordId: String
    var who: String
    var paidMinor: MoneyMinor
    var forWhom: [String]
    var type: String
    var text: String
    var long: String
    var lat: String
    var createdAt: TimeInterval
    var occurredAt: TimeInterval
    var modifiedAt: TimeInterval
    var isDebtResolve: Bool
    var createdBy: String?
    var modifiedBy: String?
    var currencyCode: String? = nil
    var spendingShareMinor: MoneyMinor? = nil

    var hasSplitAmount: Bool { !isDebtResolve && forWhom.count > 1 }

    func amountMinor(perPerson: Bool) -> MoneyMinor {
        perPerson && hasSplitAmount ? Money.averageShare(paidMinor, count: forWhom.count) : paidMinor
    }

    func expenseShareMinor(for participantID: String) -> MoneyMinor? {
        guard !isDebtResolve, let index = forWhom.firstIndex(of: participantID) else { return nil }
        return Money.splitShare(paidMinor, count: forWhom.count, index: index)
    }
}

struct GroupRecordSort: Codable, Hashable {
    enum Field: String, Codable, CaseIterable {
        case occurredAt, amount

        var title: String { L(self == .occurredAt ? "Date" : "Amount") }
    }

    enum Order: String, Codable, CaseIterable {
        case ascending = "asc"
        case descending = "desc"

        var title: String { L(self == .ascending ? "Ascending" : "Descending") }
    }

    enum AmountBasis: String {
        case total, perPerson
    }

    var field: Field = .occurredAt
    var order: Order = .descending

    static var sectionCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    func ordered(_ records: [WalkRecord], amountBasis: AmountBasis = .total) -> [WalkRecord] {
        records.sorted { recordPrecedes($0, $1, amountBasis: amountBasis) }
    }

    func sections(for records: [WalkRecord], now: Date) -> [(date: Date, records: [WalkRecord])] {
        let calendar = Self.sectionCalendar
        let grouped = Dictionary(grouping: records) {
            TemporalDisplay.sectionDate(for: $0.occurredAt.walkDate, now: now, calendar: calendar)
        }
        let dates = grouped.keys.sorted(by: field == .occurredAt && order == .ascending ? (<) : (>))
        return dates.map { ($0, ordered(grouped[$0, default: []])) }
    }

    private func recordPrecedes(_ left: WalkRecord, _ right: WalkRecord, amountBasis: AmountBasis) -> Bool {
        if field == .amount {
            let perPerson = amountBasis == .perPerson
            let comparison = Money.compare(left.amountMinor(perPerson: perPerson), right.amountMinor(perPerson: perPerson))
            if comparison != .orderedSame {
                return comparison == (order == .ascending ? .orderedAscending : .orderedDescending)
            }
        }

        let ascendingTime = field == .occurredAt && order == .ascending
        if left.occurredAt != right.occurredAt {
            return ascendingTime ? left.occurredAt < right.occurredAt : left.occurredAt > right.occurredAt
        }
        if left.createdAt != right.createdAt {
            return ascendingTime ? left.createdAt < right.createdAt : left.createdAt > right.createdAt
        }
        return ascendingTime ? left.id < right.id : left.id > right.id
    }
}

struct GroupRecordFilters: Codable, Hashable {
    var currencyCodes: Set<String> = []
    var onlyRelatedToMe = false
    var categoryIds: Set<String> = []
    var sort = GroupRecordSort()

    init(currencyCodes: Set<String> = [], onlyRelatedToMe: Bool = false, categoryIds: Set<String> = [], sort: GroupRecordSort = GroupRecordSort()) {
        self.currencyCodes = currencyCodes
        self.onlyRelatedToMe = onlyRelatedToMe
        self.categoryIds = categoryIds
        self.sort = sort
    }

    private enum CodingKeys: String, CodingKey { case currencyCodes, onlyRelatedToMe, categoryIds, sort }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCodes = try values.decodeIfPresent(Set<String>.self, forKey: .currencyCodes) ?? []
        onlyRelatedToMe = try values.decodeIfPresent(Bool.self, forKey: .onlyRelatedToMe) ?? false
        categoryIds = try values.decodeIfPresent(Set<String>.self, forKey: .categoryIds) ?? []
        sort = try values.decodeIfPresent(GroupRecordSort.self, forKey: .sort) ?? GroupRecordSort()
    }

    var hasFilters: Bool { onlyRelatedToMe || !currencyCodes.isEmpty || !categoryIds.isEmpty }
    var isActive: Bool { hasFilters || sort != GroupRecordSort() }
    var currencySummary: String {
        currencyCodes.isEmpty ? L("All currencies") : currencyCodes.sorted().joined(separator: ", ")
    }
    var categorySummary: String {
        categoryIds.isEmpty ? L("All categories") : recordFilterCategories.filter { categoryIds.contains($0.id) }.map { L($0.titleKey) }.joined(separator: ", ")
    }
    var summary: String {
        [currencyCodes.isEmpty ? nil : currencySummary, onlyRelatedToMe ? L("Related to me") : nil,
         categoryIds.isEmpty ? nil : categorySummary,
         sort == GroupRecordSort() ? nil : "\(sort.field.title), \(sort.order.title)"]
            .compactMap { $0 }.joined(separator: " · ")
    }
    func includesCurrency(_ code: String?) -> Bool {
        currencyCodes.isEmpty || currencyCodes.contains(CurrencyCatalog.normalizedCode(code))
    }
}

struct RecordSearchRequest: Encodable, Hashable {
    enum ExpenseScope: Hashable {
        case mine(participantID: String)
        case member(participantID: String)

        var participantID: String {
            switch self {
            case .mine(let id), .member(let id): id
            }
        }
    }

    var `operator`: String
    var conditions: [RecordSearchCondition]
    var currencyCodes: [String] = []
    var participantId: String? = nil
    var categoryIds: [String] = []
    var includeSettlements = false
    var includeUncategorized = false
    var expenseScope: ExpenseScope? = nil
    var occurredWithin: DateInterval? = nil
    var sort: GroupRecordSort? = nil
    var amountBasis: GroupRecordSort.AmountBasis? = nil

    private enum CodingKeys: String, CodingKey { case `operator`, conditions }

    func filteredRecords(_ records: [WalkRecord], defaultCurrency: String?) -> [WalkRecord] {
        let filtered = records.filter { matches($0, defaultCurrency: defaultCurrency) }
        return sort?.ordered(filtered, amountBasis: amountBasis ?? .total) ?? filtered
    }

    func matches(_ record: WalkRecord, defaultCurrency: String?) -> Bool {
        guard currencyCodes.isEmpty || currencyCodes.contains(CurrencyCatalog.normalizedCode(record.currencyCode ?? defaultCurrency)) else { return false }
        if let participantId, record.who != participantId && !record.forWhom.contains(participantId) { return false }
        if let expenseScope, record.isDebtResolve || !record.forWhom.contains(expenseScope.participantID) { return false }
        if let occurredWithin {
            let date = record.occurredAt.walkDate
            guard date >= occurredWithin.start, date < occurredWithin.end else { return false }
        }
        if !categoryIds.isEmpty || includeSettlements || includeUncategorized {
            let matchesCategory = record.isDebtResolve
                ? includeSettlements || categoryIds.contains(settlementCategory.id)
                : categoryIds.contains(record.type) || (includeUncategorized && record.type.isEmpty)
            guard matchesCategory else { return false }
        }
        guard !conditions.isEmpty else { return true }
        let matches = conditions.map { condition in
            switch condition.field {
            case "note": record.text.localizedCaseInsensitiveContains(condition.query)
            case "categoryName": L(expenseCategory(for: record).titleKey).localizedCaseInsensitiveContains(condition.query)
            default: false
            }
        }
        return `operator` == "and" ? matches.allSatisfy { $0 } : matches.contains(true)
    }

    static func noteOrCategoryName(query: String) -> RecordSearchRequest {
        RecordSearchRequest(
            operator: "or",
            conditions: [
                RecordSearchCondition(field: "note", query: query),
                RecordSearchCondition(field: "categoryName", query: query)
            ]
        )
    }
}

struct RecordSearchCondition: Encodable, Hashable {
    var field: String
    var query: String
}

struct ResolvedDebt: Identifiable, Hashable {
    var from: Member
    var to: Member
    var amountMinor: MoneyMinor
    var currencyCode: String = CurrencyCatalog.defaultCurrencyCode()

    var id: String {
        "\(CurrencyCatalog.normalizedCode(currencyCode)):\(from.uuid)->\(to.uuid):\(amountMinor)"
    }
}

enum BalancePresentation {
    static func personalDebts(_ debts: [ResolvedDebt], participantID: String?) -> [ResolvedDebt] {
        guard let participantID, !participantID.isEmpty else { return [] }
        return debts.filter { debt in
            debt.from.uuid == participantID || debt.to.uuid == participantID
        }
    }

    static func sortedByAbsoluteAmount(_ debts: [ResolvedDebt]) -> [ResolvedDebt] {
        debts.sorted { left, right in
            let amountOrder = Money.compare(
                Money.absolute(left.amountMinor),
                Money.absolute(right.amountMinor)
            )
            if amountOrder != .orderedSame {
                return amountOrder == .orderedDescending
            }
            let leftCurrency = CurrencyCatalog.normalizedCode(left.currencyCode)
            let rightCurrency = CurrencyCatalog.normalizedCode(right.currencyCode)
            if leftCurrency != rightCurrency {
                return leftCurrency < rightCurrency
            }
            if left.from.uuid != right.from.uuid {
                return left.from.uuid < right.from.uuid
            }
            return left.to.uuid < right.to.uuid
        }
    }

}

struct SettlementTransfer: Hashable {
    var fromId: String
    var toId: String
    var amountMinor: MoneyMinor
    var currencyCode: String? = nil
}

struct MemberRecordPage {
    var member: Member?
    var records: [WalkRecord]
}

enum AppTheme: String, CaseIterable, Identifiable, Codable, Hashable {
    case mono = "black"
    case blue
    case pink
    case yellow
    case green

    static let defaultTheme: AppTheme = SoftLedgerThemeConfig.defaultAppTheme
    static let storageKey = "walkcalc.selectedTheme"
    static let legacyStorageKey = "themeColor"

    var id: String { rawValue }

    var titleKey: String {
        palette.titleKey
    }

    var accent: Color {
        palette.accent.color
    }

    var accentUIColor: UIColor {
        palette.accent.uiColor
    }

    var systemControlTintUIColor: UIColor {
        accentUIColor
    }

    var alertContainerTintUIColor: UIColor {
        accentUIColor
    }

    var alertButtonTintUIColor: UIColor {
        accentUIColor
    }

    func applySystemControlTint() {
        UIView.appearance().tintColor = systemControlTintUIColor
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = alertContainerTintUIColor
        UIButton.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = alertButtonTintUIColor
    }

    var accentSoft: Color {
        palette.accentSoft.color
    }

    static func load(from defaults: UserDefaults = .standard) -> AppTheme {
        // Theme selection is temporarily unavailable. Keep saved preferences intact
        // for a future palette redesign, but use the monochrome theme everywhere.
        return .mono
    }

    static func theme(forLegacyValue value: String) -> AppTheme {
        switch value {
        case "blue":
            return .blue
        case "green":
            return .green
        case "gold":
            return .yellow
        default:
            return defaultTheme
        }
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    private var palette: AppThemePalette {
        SoftLedgerThemeConfig.palette(for: self)
    }
}

let categoryEmoji: [String: String] = [
    "food": "🍚",
    "beverage": "🥃",
    "shopping": "🛒",
    "traffic": "🚗",
    "accommodation": "🏠",
    "vacation": "🏝",
    "transfer": "💰",
    "ticket": "🎫",
    "game": "🎲",
    "debtResolve": "🤝"
]

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xff) / 255
        let green = CGFloat((hex >> 8) & 0xff) / 255
        let blue = CGFloat(hex & 0xff) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

extension TimeInterval {
    var walkDate: Date {
        Date(timeIntervalSince1970: self / 1000)
    }
}
