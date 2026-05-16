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

enum AppTheme: String, CaseIterable, Identifiable, Codable, Hashable {
    case blue
    case black
    case yellow
    case green

    static let defaultTheme: AppTheme = .blue
    static let storageKey = "walkcalc.selectedTheme"
    static let legacyStorageKey = "themeColor"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .yellow:
            return "Yellow"
        case .blue:
            return "Blue"
        case .green:
            return "Green"
        case .black:
            return "Black"
        }
    }

    var accent: Color {
        switch self {
        case .yellow:
            return Self.adaptiveColor(light: 0xB15525, dark: 0xE49B63)
        case .blue:
            return Self.adaptiveColor(light: 0x2C6AA0, dark: 0x6EA3D0)
        case .green:
            return Self.adaptiveColor(light: 0x1D6F50, dark: 0x6FBC8D)
        case .black:
            return Self.adaptiveColor(light: 0x18181B, dark: 0xFAFAFA)
        }
    }

    var accentUIColor: UIColor {
        switch self {
        case .yellow:
            return Self.adaptiveUIColor(light: 0xB15525, dark: 0xE49B63)
        case .blue:
            return Self.adaptiveUIColor(light: 0x2C6AA0, dark: 0x6EA3D0)
        case .green:
            return Self.adaptiveUIColor(light: 0x1D6F50, dark: 0x6FBC8D)
        case .black:
            return Self.adaptiveUIColor(light: 0x18181B, dark: 0xFAFAFA)
        }
    }

    var accentSoft: Color {
        switch self {
        case .yellow:
            return Self.adaptiveColor(light: 0xEDCBA4, dark: 0x38322F)
        case .blue:
            return Self.adaptiveColor(light: 0xDCE7F1, dark: 0x1A2F40)
        case .green:
            return Self.adaptiveColor(light: 0xDCEBE3, dark: 0x1A3327)
        case .black:
            return Self.adaptiveColor(light: 0xF4F4F5, dark: 0x27272A)
        }
    }

    var previewAccent: Color {
        switch self {
        case .yellow:
            return Color(hex: 0xB15525)
        case .blue:
            return Color(hex: 0x2C6AA0)
        case .green:
            return Color(hex: 0x1D6F50)
        case .black:
            return Color(hex: 0x18181B)
        }
    }

    var previewSoftAccent: Color {
        switch self {
        case .yellow:
            return Color(hex: 0xEDCBA4)
        case .blue:
            return Color(hex: 0xDCE7F1)
        case .green:
            return Color(hex: 0xDCEBE3)
        case .black:
            return Color(hex: 0xF4F4F5)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> AppTheme {
        if let storedValue = defaults.string(forKey: storageKey),
           let storedTheme = AppTheme(rawValue: storedValue) {
            return storedTheme
        }

        if let legacyValue = defaults.string(forKey: legacyStorageKey) {
            return theme(forLegacyValue: legacyValue)
        }

        return defaultTheme
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

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func adaptiveUIColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        }
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
