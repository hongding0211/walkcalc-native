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

struct UserProfile: Identifiable, Hashable {
    var id: String { uuid }
    var uuid: String
    var name: String
    var avatar: String
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
}

struct WalkGroup: Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval
    var membersInfo: [Member]
    var tempUsers: [Member]
    var archivedUsers: [String]
    var isOwner: Bool
    var hasCurrentUserBalanceSummary: Bool = false
    var currentUserBalanceMinor: MoneyMinor = "0"
    var currentUserExpenseShareMinor: MoneyMinor = "0"
    var currentUserPaidTotalMinor: MoneyMinor = "0"
    var currentUserRecordCount: Int = 0
    var participantCount: Int = 0
    var participantPreview: [Member] = []
    var serverHasUnresolvedBalance: Bool?

    var allMembers: [Member] {
        membersInfo + tempUsers
    }

    var hasUnresolvedBalance: Bool {
        if let serverHasUnresolvedBalance {
            return serverHasUnresolvedBalance
        }
        return allMembers.contains { !Money.isZero($0.debtMinor) }
    }

    var shouldShowDeleteResolutionNotice: Bool {
        if let serverHasUnresolvedBalance {
            return serverHasUnresolvedBalance
        }
        if allMembers.isEmpty {
            return participantCount > 1 || !Money.isZero(currentUserBalanceMinor)
        }
        return hasUnresolvedBalance
    }

    var shouldBlockArchive: Bool {
        if let serverHasUnresolvedBalance {
            return serverHasUnresolvedBalance
        }
        if allMembers.isEmpty {
            return !Money.isZero(currentUserBalanceMinor)
        }
        return hasUnresolvedBalance
    }
}

struct WalkRecord: Identifiable, Hashable {
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
}

struct RecordSearchRequest: Encodable, Hashable {
    var `operator`: String
    var conditions: [RecordSearchCondition]

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
    var id = UUID()
    var from: Member
    var to: Member
    var amountMinor: MoneyMinor
}

struct SettlementTransfer: Hashable {
    var fromId: String
    var toId: String
    var amountMinor: MoneyMinor
}

struct MemberRecordPage {
    var member: Member?
    var records: [WalkRecord]
}

struct ThemeColorOption: Identifiable, Hashable {
    var id: String
    var label: String
    var color: Color
    var uiColor: UIColor
}

let themeColorOptions: [ThemeColorOption] = [
    .init(id: "blue", label: "Blue", color: Color(hex: 0x316FE2), uiColor: UIColor(hex: 0x316FE2)),
    .init(id: "green", label: "Green", color: Color(hex: 0x22A06B), uiColor: UIColor(hex: 0x22A06B)),
    .init(id: "rose", label: "Rose", color: Color(hex: 0xE0527C), uiColor: UIColor(hex: 0xE0527C)),
    .init(id: "gold", label: "Gold", color: Color(hex: 0xF8D03A), uiColor: UIColor(hex: 0xC99700))
]

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
