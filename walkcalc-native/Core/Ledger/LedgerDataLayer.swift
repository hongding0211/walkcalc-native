import Foundation

enum LedgerSourceKind: String, Hashable {
    case local
    case remote
}

struct LedgerSourceMetadata: Hashable {
    var source: LedgerSourceKind
    var localIdentifier: String?
    var remoteIdentifier: String?

    static func remote(id: String? = nil) -> LedgerSourceMetadata {
        LedgerSourceMetadata(source: .remote, localIdentifier: nil, remoteIdentifier: id)
    }

    static func local(id: String? = nil) -> LedgerSourceMetadata {
        LedgerSourceMetadata(source: .local, localIdentifier: id, remoteIdentifier: nil)
    }
}

struct LedgerSessionContext {
    var accessToken: String?
    var localOwner: Member?
    var localSourceAvailable: Bool
    var preferredSource: LedgerSourceKind

    static func remote(accessToken: String?) -> LedgerSessionContext {
        LedgerSessionContext(
            accessToken: accessToken,
            localOwner: nil,
            localSourceAvailable: false,
            preferredSource: .remote
        )
    }

    static func local(owner: Member) -> LedgerSessionContext {
        LedgerSessionContext(
            accessToken: nil,
            localOwner: owner,
            localSourceAvailable: true,
            preferredSource: .local
        )
    }
}

enum LedgerOperationFailureKind: Equatable {
    case validation
    case authenticationRequired
    case sourceUnavailable
    case recoverableNetwork
    case unrecoverableAuth
    case serverRejected
}

struct LedgerOperationFailure: Equatable {
    var kind: LedgerOperationFailureKind
    var message: String?
    var statusCode: Int?
    var errorData: [String: Any]?

    static func == (lhs: LedgerOperationFailure, rhs: LedgerOperationFailure) -> Bool {
        lhs.kind == rhs.kind
            && lhs.message == rhs.message
            && lhs.statusCode == rhs.statusCode
    }
}

enum LedgerOperationResult<Value> {
    case success(Value)
    case failure(LedgerOperationFailure)

    var value: Value? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    var failure: LedgerOperationFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}

struct LedgerPage<Value> {
    var items: [Value]
    var pagination: Pagination?
    var source: LedgerSourceMetadata
    var refreshedToken: String?
}

struct CurrencyBalanceSummary: Identifiable, Hashable, Sendable {
    var id: String { currencyCode }
    var currencyCode: String
    var totalBalanceMinor: MoneyMinor
}

struct HomeBalanceSummary: Sendable {
    var totalBalanceMinor: MoneyMinor
    var balances: [CurrencyBalanceSummary]
}

struct LedgerHomeSnapshot {
    var groups: [WalkGroup]
    var groupPagination: Pagination?
    var totalBalanceMinor: MoneyMinor?
    var currencyBalances: [CurrencyBalanceSummary] = []
    var source: LedgerSourceMetadata
    var refreshedToken: String?
}

struct LedgerGroupSnapshot {
    var group: WalkGroup?
    var records: [WalkRecord]
    var recordPagination: Pagination?
    var source: LedgerSourceMetadata
    var refreshedToken: String?
}

struct LedgerMemberRecordSnapshot {
    var member: Member?
    var records: [WalkRecord]
    var pagination: Pagination?
    var source: LedgerSourceMetadata
    var refreshedToken: String?
}

struct LedgerMutationResponse<Value> {
    var value: Value?
    var message: String?
    var errorData: [String: Any]?
    var source: LedgerSourceMetadata
    var refreshedToken: String?
}

protocol LedgerDataSource {
    var sourceKind: LedgerSourceKind { get }

    func home(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerHomeSnapshot>
    func groups(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkGroup>>
    func groupDetail(groupId: String, recordPageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerGroupSnapshot>
    func groupBalances(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[Member]>>
    func records(groupId: String, page: Int, pageSize: Int, search: RecordSearchRequest?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkRecord>>
    func memberRecords(groupId: String, memberId: String, page: Int, pageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMemberRecordSnapshot>
    func settlementSuggestion(groupId: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[SettlementTransfer]>>

    func createGroup(name: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func joinGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func archiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func unarchiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func deleteGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func changeGroupName(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func changeGroupCurrency(code: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func invite(code: String, userIds: [String], context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[String]>>
    func addTempUser(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func removeMember(code: String, participantId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func searchUsers(name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[UserProfile]>>

    func addRecord(groupId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>>
    func addSettlementRecord(groupId: String, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>>
    func updateRecord(groupId: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>>
    func deleteRecord(groupId: String, recordId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>>
    func resolveDebts(groupId: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[WalkRecord]>>
}

struct RemoteLedgerDataSource: LedgerDataSource {
    let sourceKind = LedgerSourceKind.remote
    let api: APIClient

    func home(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerHomeSnapshot> {
        guard let token = context.accessToken else { return .failure(.authenticationRequired()) }
        do {
            async let groupsResponse = api.groups(page: page, pageSize: pageSize, search: search, token: token)
            async let summaryResponse = api.homeSummary(token: token)
            let (groups, summary) = try await (groupsResponse, summaryResponse)
            if let failure = failure(from: groups) ?? failure(from: summary) {
                return .failure(failure)
            }
            return .success(LedgerHomeSnapshot(
                groups: groups.data ?? [],
                groupPagination: groups.pagination,
                totalBalanceMinor: summary.data?.totalBalanceMinor,
                currencyBalances: summary.data?.balances ?? [],
                source: .remote(),
                refreshedToken: groups.refreshedToken ?? summary.refreshedToken
            ))
        } catch {
            return .failure(failure(from: error))
        }
    }

    func groups(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkGroup>> {
        await envelopePage(context: context) { token in
            try await api.groups(page: page, pageSize: pageSize, search: search, token: token)
        }
    }

    func groupDetail(groupId: String, recordPageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerGroupSnapshot> {
        guard let token = context.accessToken else { return .failure(.authenticationRequired()) }
        do {
            async let groupResponse = api.group(code: groupId, token: token)
            async let recordsResponse = api.records(groupCode: groupId, page: 1, pageSize: recordPageSize, token: token)
            let (group, records) = try await (groupResponse, recordsResponse)
            if let failure = failure(from: group) ?? failure(from: records) {
                return .failure(failure)
            }
            return .success(LedgerGroupSnapshot(
                group: group.data,
                records: records.data ?? [],
                recordPagination: records.pagination,
                source: .remote(id: groupId),
                refreshedToken: group.refreshedToken ?? records.refreshedToken
            ))
        } catch {
            return .failure(failure(from: error))
        }
    }

    func groupBalances(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[Member]>> {
        await envelopeMutation(context: context) { token in
            try await api.groupBalances(groupCode: groupId, token: token)
        }
    }

    func records(groupId: String, page: Int, pageSize: Int, search: RecordSearchRequest?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkRecord>> {
        await envelopePage(context: context) { token in
            try await api.records(groupCode: groupId, page: page, pageSize: pageSize, recordSearch: search, token: token)
        }
    }

    func memberRecords(groupId: String, memberId: String, page: Int, pageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMemberRecordSnapshot> {
        guard let token = context.accessToken else { return .failure(.authenticationRequired()) }
        do {
            let response = try await api.participantRecords(groupCode: groupId, participantId: memberId, page: page, pageSize: pageSize, token: token)
            if let failure = failure(from: response) {
                return .failure(failure)
            }
            return .success(LedgerMemberRecordSnapshot(
                member: response.data?.member,
                records: response.data?.records ?? [],
                pagination: response.pagination,
                source: .remote(id: groupId),
                refreshedToken: response.refreshedToken
            ))
        } catch {
            return .failure(failure(from: error))
        }
    }

    func settlementSuggestion(groupId: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[SettlementTransfer]>> {
        guard let token = context.accessToken else { return .failure(.authenticationRequired()) }
        do {
            let response = try await api.settlementSuggestion(groupCode: groupId, currencyCode: currencyCode, token: token)
            if let failure = failure(from: response) {
                return .failure(failure)
            }
            return .success(LedgerMutationResponse(
                value: (response.data ?? []).map { SettlementTransfer(fromId: $0.fromId, toId: $0.toId, amountMinor: $0.amountMinor, currencyCode: $0.currencyCode) },
                message: response.message,
                errorData: response.errorData,
                source: .remote(id: groupId),
                refreshedToken: response.refreshedToken
            ))
        } catch {
            return .failure(failure(from: error))
        }
    }

    func createGroup(name: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.createGroup(name: name, currencyCode: currencyCode, token: token)
        }
    }

    func joinGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.joinGroup(code: code, token: token)
        }
    }

    func archiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.archiveGroup(code: code, token: token)
        }
    }

    func unarchiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.unarchiveGroup(code: code, token: token)
        }
    }

    func deleteGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.deleteGroup(code: code, token: token)
        }
    }

    func changeGroupName(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.changeGroupName(code: code, name: name, token: token)
        }
    }

    func changeGroupCurrency(code: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.changeGroupCurrency(code: code, currencyCode: currencyCode, token: token)
        }
    }

    func invite(code: String, userIds: [String], context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[String]>> {
        await envelopeMutation(context: context) { token in
            try await api.invite(code: code, userIds: userIds, token: token)
        }
    }

    func addTempUser(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.addTempUser(code: code, name: name, token: token)
        }
    }

    func removeMember(code: String, participantId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.removeMember(code: code, participantId: participantId, token: token)
        }
    }

    func searchUsers(name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[UserProfile]>> {
        await envelopeMutation(context: context) { token in
            try await api.searchUsers(name: name, token: token)
        }
    }

    func addRecord(groupId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        await envelopeMutation(context: context) { token in
            try await api.addRecord(groupCode: groupId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, currencyCode: currencyCode, token: token, long: long, lat: lat, occurredAt: occurredAt)
        }
    }

    func addSettlementRecord(groupId: String, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        await envelopeMutation(context: context) { token in
            try await api.addSettlementRecord(groupCode: groupId, fromId: fromId, toId: toId, amountMinor: amountMinor, note: note, currencyCode: currencyCode, token: token)
        }
    }

    func updateRecord(groupId: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        await envelopeMutation(context: context) { token in
            try await api.updateRecord(groupCode: groupId, recordId: recordId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, currencyCode: currencyCode, token: token, occurredAt: occurredAt, isSettlement: isSettlement)
        }
    }

    func deleteRecord(groupId: String, recordId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await envelopeMutation(context: context) { token in
            try await api.dropRecord(groupCode: groupId, recordId: recordId, token: token)
        }
    }

    func resolveDebts(groupId: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[WalkRecord]>> {
        await envelopeMutation(context: context) { token in
            try await api.resolveDebts(groupCode: groupId, currencyCode: currencyCode, token: token)
        }
    }

    private func envelopePage<Value>(context: LedgerSessionContext, operation: (String) async throws -> APIEnvelope<[Value]>) async -> LedgerOperationResult<LedgerPage<Value>> {
        guard let token = context.accessToken else { return .failure(.authenticationRequired()) }
        do {
            let response = try await operation(token)
            if let failure = failure(from: response) {
                return .failure(failure)
            }
            return .success(LedgerPage(
                items: response.data ?? [],
                pagination: response.pagination,
                source: .remote(),
                refreshedToken: response.refreshedToken
            ))
        } catch {
            return .failure(failure(from: error))
        }
    }

    private func envelopeMutation<Value>(context: LedgerSessionContext, operation: (String) async throws -> APIEnvelope<Value>) async -> LedgerOperationResult<LedgerMutationResponse<Value>> {
        guard let token = context.accessToken else { return .failure(.authenticationRequired()) }
        do {
            let response = try await operation(token)
            if let failure = failure(from: response) {
                return .failure(failure)
            }
            return .success(LedgerMutationResponse(
                value: response.data,
                message: response.message,
                errorData: response.errorData,
                source: .remote(),
                refreshedToken: response.refreshedToken
            ))
        } catch {
            return .failure(failure(from: error))
        }
    }

    private func failure<Value>(from response: APIEnvelope<Value>) -> LedgerOperationFailure? {
        guard !response.success else { return nil }
        if response.failureKind == .authRefresh || response.statusCode == 401 || response.statusCode == 403 {
            return LedgerOperationFailure(kind: .unrecoverableAuth, message: response.message, statusCode: response.statusCode, errorData: response.errorData)
        }
        if response.statusCode.map({ $0 >= 400 }) == true {
            return LedgerOperationFailure(kind: .serverRejected, message: response.message, statusCode: response.statusCode, errorData: response.errorData)
        }
        return LedgerOperationFailure(kind: .recoverableNetwork, message: response.message, statusCode: response.statusCode, errorData: response.errorData)
    }

    private func failure(from error: Error) -> LedgerOperationFailure {
        guard let clientError = error as? APIClientError else {
            return LedgerOperationFailure(kind: .recoverableNetwork, message: nil, statusCode: nil, errorData: nil)
        }
        if clientError.kind == .authRefresh || clientError.statusCode == 401 || clientError.statusCode == 403 {
            return LedgerOperationFailure(kind: .unrecoverableAuth, message: clientError.message, statusCode: clientError.statusCode, errorData: nil)
        }
        return LedgerOperationFailure(kind: .recoverableNetwork, message: clientError.message, statusCode: clientError.statusCode, errorData: nil)
    }
}

final class LedgerRepository {
    private let remoteSource: any LedgerDataSource
    private let localSource: (any LedgerDataSource)?

    init(remoteSource: any LedgerDataSource, localSource: (any LedgerDataSource)? = nil) {
        self.remoteSource = remoteSource
        self.localSource = localSource
    }

    func home(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerHomeSnapshot> {
        await source(for: context).home(page: page, pageSize: pageSize, search: search, context: context)
    }

    func groups(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkGroup>> {
        await source(for: context).groups(page: page, pageSize: pageSize, search: search, context: context)
    }

    func groupDetail(groupId: String, recordPageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerGroupSnapshot> {
        await source(for: context).groupDetail(groupId: groupId, recordPageSize: recordPageSize, context: context)
    }

    func groupBalances(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[Member]>> {
        await source(for: context).groupBalances(groupId: groupId, context: context)
    }

    func records(groupId: String, page: Int, pageSize: Int, search: RecordSearchRequest?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkRecord>> {
        await source(for: context).records(groupId: groupId, page: page, pageSize: pageSize, search: search, context: context)
    }

    func memberRecords(groupId: String, memberId: String, page: Int, pageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMemberRecordSnapshot> {
        await source(for: context).memberRecords(groupId: groupId, memberId: memberId, page: page, pageSize: pageSize, context: context)
    }

    func settlementSuggestion(groupId: String, currencyCode: String? = nil, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[SettlementTransfer]>> {
        await source(for: context).settlementSuggestion(groupId: groupId, currencyCode: currencyCode, context: context)
    }

    func createGroup(name: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).createGroup(name: name, currencyCode: currencyCode, context: context)
    }

    func joinGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await remoteSource.joinGroup(code: code, context: context)
    }

    func archiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).archiveGroup(code: code, context: context)
    }

    func unarchiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).unarchiveGroup(code: code, context: context)
    }

    func deleteGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).deleteGroup(code: code, context: context)
    }

    func changeGroupName(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).changeGroupName(code: code, name: name, context: context)
    }

    func changeGroupCurrency(code: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).changeGroupCurrency(code: code, currencyCode: currencyCode, context: context)
    }

    func invite(code: String, userIds: [String], context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[String]>> {
        await remoteSource.invite(code: code, userIds: userIds, context: context)
    }

    func addTempUser(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).addTempUser(code: code, name: name, context: context)
    }

    func removeMember(code: String, participantId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).removeMember(code: code, participantId: participantId, context: context)
    }

    func searchUsers(name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[UserProfile]>> {
        await remoteSource.searchUsers(name: name, context: context)
    }

    func addRecord(groupId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, currencyCode: String? = nil, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        await source(for: context).addRecord(groupId: groupId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, long: long, lat: lat, occurredAt: occurredAt, currencyCode: currencyCode, context: context)
    }

    func addSettlementRecord(groupId: String, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, currencyCode: String? = nil, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        await source(for: context).addSettlementRecord(groupId: groupId, fromId: fromId, toId: toId, amountMinor: amountMinor, note: note, currencyCode: currencyCode, context: context)
    }

    func updateRecord(groupId: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool, currencyCode: String? = nil, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        await source(for: context).updateRecord(groupId: groupId, recordId: recordId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, occurredAt: occurredAt, isSettlement: isSettlement, currencyCode: currencyCode, context: context)
    }

    func deleteRecord(groupId: String, recordId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await source(for: context).deleteRecord(groupId: groupId, recordId: recordId, context: context)
    }

    func resolveDebts(groupId: String, currencyCode: String? = nil, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[WalkRecord]>> {
        await source(for: context).resolveDebts(groupId: groupId, currencyCode: currencyCode, context: context)
    }

    private func source(for context: LedgerSessionContext) -> any LedgerDataSource {
        if context.preferredSource == .local, let localSource {
            return localSource
        }
        return remoteSource
    }
}

extension LedgerOperationFailure {
    static func authenticationRequired(message: String? = nil) -> LedgerOperationFailure {
        LedgerOperationFailure(kind: .authenticationRequired, message: message ?? L("Login to continue"), statusCode: nil, errorData: nil)
    }

    static func sourceUnavailable(message: String? = nil) -> LedgerOperationFailure {
        LedgerOperationFailure(kind: .sourceUnavailable, message: message, statusCode: nil, errorData: nil)
    }
}
