import Foundation
import SwiftData

@Model
final class LocalLedgerGroupModel {
    @Attribute(.unique) var id: String
    var name: String
    var currencyCode: String?
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval
    var ownerUserId: String
    var archivedUserIdsJSON: String
    var remoteIdentifier: String?
    var syncState: String
    var isDirty: Bool

    @Relationship(deleteRule: .cascade, inverse: \LocalLedgerParticipantModel.group)
    var participants: [LocalLedgerParticipantModel]

    @Relationship(deleteRule: .cascade, inverse: \LocalLedgerRecordModel.group)
    var records: [LocalLedgerRecordModel]

    init(
        id: String,
        name: String,
        currencyCode: String? = nil,
        createdAt: TimeInterval,
        modifiedAt: TimeInterval,
        ownerUserId: String,
        archivedUserIds: [String] = [],
        remoteIdentifier: String? = nil,
        syncState: String = "local",
        isDirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.ownerUserId = ownerUserId
        self.archivedUserIdsJSON = Self.encodeStrings(archivedUserIds)
        self.remoteIdentifier = remoteIdentifier
        self.syncState = syncState
        self.isDirty = isDirty
        self.participants = []
        self.records = []
    }

    var archivedUserIds: [String] {
        get { Self.decodeStrings(archivedUserIdsJSON) }
        set { archivedUserIdsJSON = Self.encodeStrings(newValue) }
    }

    static func encodeStrings(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func decodeStrings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}

@Model
final class LocalLedgerParticipantModel {
    @Attribute(.unique) var id: String
    var name: String
    var avatar: String
    var debtMinor: MoneyMinor
    var costMinor: MoneyMinor
    var recordCount: Int
    var currencyBalancesJSON: String?
    var isTemporary: Bool
    var isActive: Bool = true
    var createdAt: TimeInterval
    var modifiedAt: TimeInterval
    var remoteIdentifier: String?
    var syncState: String
    var isDirty: Bool
    var group: LocalLedgerGroupModel?

    init(
        id: String,
        name: String,
        avatar: String = "",
        debtMinor: MoneyMinor = "0",
        costMinor: MoneyMinor = "0",
        recordCount: Int = 0,
        isTemporary: Bool,
        isActive: Bool = true,
        createdAt: TimeInterval,
        modifiedAt: TimeInterval,
        remoteIdentifier: String? = nil,
        syncState: String = "local",
        isDirty: Bool = true
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.debtMinor = debtMinor
        self.costMinor = costMinor
        self.recordCount = recordCount
        self.currencyBalancesJSON = nil
        self.isTemporary = isTemporary
        self.isActive = isActive
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.remoteIdentifier = remoteIdentifier
        self.syncState = syncState
        self.isDirty = isDirty
    }

    var currencyBalances: [MemberCurrencyProjection] {
        get {
            guard let currencyBalancesJSON,
                  let data = currencyBalancesJSON.data(using: .utf8),
                  let values = try? JSONDecoder().decode([MemberCurrencyProjection].self, from: data) else {
                return []
            }
            return values
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else {
                currencyBalancesJSON = nil
                return
            }
            currencyBalancesJSON = value
        }
    }
}

@Model
final class LocalLedgerRecordModel {
    @Attribute(.unique) var id: String
    var who: String
    var paidMinor: MoneyMinor
    var forWhomJSON: String
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
    var currencyCode: String?
    var remoteIdentifier: String?
    var syncState: String
    var isDirty: Bool
    var group: LocalLedgerGroupModel?

    init(
        id: String,
        who: String,
        paidMinor: MoneyMinor,
        forWhom: [String],
        type: String,
        text: String,
        long: String,
        lat: String,
        createdAt: TimeInterval,
        occurredAt: TimeInterval,
        modifiedAt: TimeInterval,
        isDebtResolve: Bool,
        createdBy: String?,
        modifiedBy: String?,
        currencyCode: String? = nil,
        remoteIdentifier: String? = nil,
        syncState: String = "local",
        isDirty: Bool = true
    ) {
        self.id = id
        self.who = who
        self.paidMinor = paidMinor
        self.forWhomJSON = LocalLedgerGroupModel.encodeStrings(forWhom)
        self.type = type
        self.text = text
        self.long = long
        self.lat = lat
        self.createdAt = createdAt
        self.occurredAt = occurredAt
        self.modifiedAt = modifiedAt
        self.isDebtResolve = isDebtResolve
        self.createdBy = createdBy
        self.modifiedBy = modifiedBy
        self.currencyCode = currencyCode
        self.remoteIdentifier = remoteIdentifier
        self.syncState = syncState
        self.isDirty = isDirty
    }

    var forWhom: [String] {
        get { LocalLedgerGroupModel.decodeStrings(forWhomJSON) }
        set { forWhomJSON = LocalLedgerGroupModel.encodeStrings(newValue) }
    }
}
