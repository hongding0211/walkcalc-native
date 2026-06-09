import Foundation

final class InMemoryLedgerDataSource: LedgerDataSource {
    let sourceKind = LedgerSourceKind.local

    private var groups: [WalkGroup]
    private var recordsByGroup: [String: [WalkRecord]]

    init(groups: [WalkGroup] = [], recordsByGroup: [String: [WalkRecord]] = [:]) {
        self.groups = groups
        self.recordsByGroup = recordsByGroup
        recomputeAllBalances()
    }

    func home(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerHomeSnapshot> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let filtered = filteredGroups(search: search)
        let slice = pageSlice(filtered, page: page, pageSize: pageSize)
        return .success(LedgerHomeSnapshot(
            groups: slice.items,
            groupPagination: Pagination(page: page, size: pageSize, total: filtered.count),
            totalBalanceMinor: totalBalance(ownerId: context.localOwner?.uuid),
            source: .local(),
            refreshedToken: nil
        ))
    }

    func groups(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkGroup>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let filtered = filteredGroups(search: search)
        let slice = pageSlice(filtered, page: page, pageSize: pageSize)
        return .success(LedgerPage(items: slice.items, pagination: Pagination(page: page, size: pageSize, total: filtered.count), source: .local(), refreshedToken: nil))
    }

    func groupDetail(groupId: String, recordPageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerGroupSnapshot> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
        let records = recordsByGroup[groupId] ?? []
        let slice = pageSlice(records, page: 1, pageSize: recordPageSize)
        return .success(LedgerGroupSnapshot(
            group: group,
            records: slice.items,
            recordPagination: Pagination(page: 1, size: recordPageSize, total: records.count),
            source: .local(id: groupId),
            refreshedToken: nil
        ))
    }

    func groupBalances(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[Member]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
        return .success(mutation(group.allMembers, source: .local(id: groupId)))
    }

    func records(groupId: String, page: Int, pageSize: Int, search: RecordSearchRequest?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let filtered = (recordsByGroup[groupId] ?? []).filter { record in
            guard let search else { return true }
            return search.conditions.contains { condition in
                conditionMatches(record: record, condition: condition)
            }
        }
        let slice = pageSlice(filtered, page: page, pageSize: pageSize)
        return .success(LedgerPage(items: slice.items, pagination: Pagination(page: page, size: pageSize, total: filtered.count), source: .local(id: groupId), refreshedToken: nil))
    }

    func memberRecords(groupId: String, memberId: String, page: Int, pageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMemberRecordSnapshot> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let records = (recordsByGroup[groupId] ?? []).filter { $0.who == memberId || $0.forWhom.contains(memberId) }
        let slice = pageSlice(records, page: page, pageSize: pageSize)
        return .success(LedgerMemberRecordSnapshot(
            member: group(id: groupId)?.allMembers.first { $0.uuid == memberId },
            records: slice.items,
            pagination: Pagination(page: page, size: pageSize, total: records.count),
            source: .local(id: groupId),
            refreshedToken: nil
        ))
    }

    func settlementSuggestion(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[SettlementTransfer]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
        return .success(mutation(settlementSuggestions(for: group), source: .local(id: groupId)))
    }

    func createGroup(name: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let now = Date().timeIntervalSince1970 * 1000
        let id = Self.localGroupId()
        let owner = context.localOwner ?? Member(uuid: "local-user-device", name: "Me", avatar: "", debtMinor: "0", costMinor: "0")
        let group = WalkGroup(
            id: id,
            name: name,
            currencyCode: CurrencyCatalog.normalizedCode(currencyCode),
            createdAt: now,
            modifiedAt: now,
            membersInfo: [owner],
            tempUsers: [],
            archivedUsers: [],
            ownerUserId: owner.uuid,
            isOwner: true,
            participantCount: 1,
            participantPreview: [owner]
        )
        groups.insert(group, at: 0)
        recordsByGroup[id] = []
        return .success(mutation(id, source: .local(id: id)))
    }

    func joinGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        .failure(.authenticationRequired())
    }

    func archiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(.sourceUnavailable()) }
        if let ownerId = groups[index].ownerUserId, !groups[index].archivedUsers.contains(ownerId) {
            groups[index].archivedUsers.append(ownerId)
        }
        return .success(mutation(code, source: .local(id: code)))
    }

    func unarchiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(.sourceUnavailable()) }
        if let ownerId = groups[index].ownerUserId {
            groups[index].archivedUsers.removeAll { $0 == ownerId }
        }
        return .success(mutation(code, source: .local(id: code)))
    }

    func deleteGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        groups.removeAll { $0.id == code }
        recordsByGroup[code] = nil
        return .success(mutation(code, source: .local(id: code)))
    }

    func changeGroupName(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(.sourceUnavailable()) }
        groups[index].name = name
        groups[index].modifiedAt = Date().timeIntervalSince1970 * 1000
        return .success(mutation(name, source: .local(id: code)))
    }

    func changeGroupCurrency(code: String, currencyCode: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(.sourceUnavailable()) }
        groups[index].currencyCode = CurrencyCatalog.normalizedCode(currencyCode)
        groups[index].modifiedAt = Date().timeIntervalSince1970 * 1000
        return .success(mutation(groups[index].currencyCode, source: .local(id: code)))
    }

    func invite(code: String, userIds: [String], context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[String]>> {
        .failure(.authenticationRequired())
    }

    func addTempUser(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(.sourceUnavailable()) }
        let id = Self.localMemberId()
        groups[index].tempUsers.append(Member(uuid: id, name: name, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true))
        groups[index].participantCount = groups[index].allMembers.count
        groups[index].participantPreview = Array(groups[index].allMembers.prefix(4))
        return .success(mutation(id, source: .local(id: code)))
    }

    func searchUsers(name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[UserProfile]>> {
        .failure(.authenticationRequired())
    }

    func addRecord(groupId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard group(id: groupId) != nil else { return .failure(.sourceUnavailable()) }
        let now = Date().timeIntervalSince1970 * 1000
        let record = WalkRecord(
            recordId: Self.localRecordId(),
            who: who,
            paidMinor: paidMinor,
            forWhom: forWhom,
            type: type,
            text: text,
            long: long,
            lat: lat,
            createdAt: now,
            occurredAt: occurredAt,
            modifiedAt: now,
            isDebtResolve: false,
            createdBy: context.localOwner?.uuid,
            modifiedBy: context.localOwner?.uuid
        )
        recordsByGroup[groupId, default: []].insert(record, at: 0)
        recomputeBalances(groupId: groupId)
        return .success(mutation(record, source: .local(id: groupId)))
    }

    func addSettlementRecord(groupId: String, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let now = Date().timeIntervalSince1970 * 1000
        let record = WalkRecord(
            recordId: Self.localRecordId(),
            who: fromId,
            paidMinor: amountMinor,
            forWhom: [toId],
            type: transferCategory.id,
            text: note,
            long: "",
            lat: "",
            createdAt: now,
            occurredAt: now,
            modifiedAt: now,
            isDebtResolve: true,
            createdBy: context.localOwner?.uuid,
            modifiedBy: context.localOwner?.uuid
        )
        recordsByGroup[groupId, default: []].insert(record, at: 0)
        recomputeBalances(groupId: groupId)
        return .success(mutation(record, source: .local(id: groupId)))
    }

    func updateRecord(groupId: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = recordsByGroup[groupId]?.firstIndex(where: { $0.recordId == recordId }) else { return .failure(.sourceUnavailable()) }
        recordsByGroup[groupId]?[index].who = who
        recordsByGroup[groupId]?[index].paidMinor = paidMinor
        recordsByGroup[groupId]?[index].forWhom = forWhom
        recordsByGroup[groupId]?[index].type = type
        recordsByGroup[groupId]?[index].text = text
        recordsByGroup[groupId]?[index].occurredAt = occurredAt
        recordsByGroup[groupId]?[index].isDebtResolve = isSettlement
        recordsByGroup[groupId]?[index].modifiedAt = Date().timeIntervalSince1970 * 1000
        recomputeBalances(groupId: groupId)
        return .success(mutation(recordsByGroup[groupId]?[index], source: .local(id: groupId)))
    }

    func deleteRecord(groupId: String, recordId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        recordsByGroup[groupId]?.removeAll { $0.recordId == recordId }
        recomputeBalances(groupId: groupId)
        return .success(mutation(recordId, source: .local(id: groupId)))
    }

    func resolveDebts(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[WalkRecord]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
        var created: [WalkRecord] = []
        for transfer in settlementSuggestions(for: group) {
            if case .success(let response) = await addSettlementRecord(groupId: groupId, fromId: transfer.fromId, toId: transfer.toId, amountMinor: transfer.amountMinor, note: "resolve", context: context),
               let record = response.value {
                created.append(record)
            }
        }
        return .success(mutation(created, source: .local(id: groupId)))
    }

    private func isAvailable(_ context: LedgerSessionContext) -> Bool {
        context.localSourceAvailable
    }

    private func group(id: String) -> WalkGroup? {
        groups.first { $0.id == id }
    }

    private func filteredGroups(search: String?) -> [WalkGroup] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }

    private func pageSlice<Value>(_ values: [Value], page: Int, pageSize: Int) -> (items: [Value], total: Int) {
        let start = max(0, (page - 1) * pageSize)
        guard start < values.count else { return ([], values.count) }
        let end = min(values.count, start + pageSize)
        return (Array(values[start..<end]), values.count)
    }

    private func conditionMatches(record: WalkRecord, condition: RecordSearchCondition) -> Bool {
        switch condition.field {
        case "note":
            return record.text.localizedCaseInsensitiveContains(condition.query)
        case "categoryName":
            return L(expenseCategory(for: record).titleKey).localizedCaseInsensitiveContains(condition.query)
        default:
            return false
        }
    }

    private func mutation<Value>(_ value: Value?, source: LedgerSourceMetadata) -> LedgerMutationResponse<Value> {
        LedgerMutationResponse(value: value, message: nil, errorData: nil, source: source, refreshedToken: nil)
    }

    private func totalBalance(ownerId: String?) -> MoneyMinor {
        guard let ownerId else { return "0" }
        return groups.reduce("0") { total, group in
            let balance = group.allMembers.first { $0.uuid == ownerId }?.debtMinor ?? "0"
            return Money.add(total, balance)
        }
    }

    private func recomputeAllBalances() {
        for groupId in groups.map(\.id) {
            recomputeBalances(groupId: groupId)
        }
    }

    private func recomputeBalances(groupId: String) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let records = recordsByGroup[groupId] ?? []
        var members = groups[groupIndex].allMembers
        for index in members.indices {
            members[index].debtMinor = "0"
            members[index].costMinor = "0"
            members[index].recordCount = 0
        }

        for record in records {
            if record.isDebtResolve {
                applySettlement(record, to: &members)
            } else {
                applyExpense(record, to: &members)
            }
        }

        groups[groupIndex].membersInfo = members.filter { !$0.isTemporary }
        groups[groupIndex].tempUsers = members.filter(\.isTemporary)
        groups[groupIndex].participantCount = members.count
        groups[groupIndex].participantPreview = Array(members.prefix(4))
        groups[groupIndex].modifiedAt = Date().timeIntervalSince1970 * 1000
    }

    private func applyExpense(_ record: WalkRecord, to members: inout [Member]) {
        guard !record.forWhom.isEmpty else { return }
        if let payerIndex = members.firstIndex(where: { $0.uuid == record.who }) {
            members[payerIndex].debtMinor = Money.add(members[payerIndex].debtMinor, record.paidMinor)
            members[payerIndex].recordCount += 1
        }
        let share = Money.splitFirst(record.paidMinor, count: record.forWhom.count)
        for participantId in record.forWhom {
            guard let index = members.firstIndex(where: { $0.uuid == participantId }) else { continue }
            members[index].debtMinor = Money.add(members[index].debtMinor, Money.negate(share))
            members[index].costMinor = Money.add(members[index].costMinor, share)
            if participantId != record.who {
                members[index].recordCount += 1
            }
        }
    }

    private func applySettlement(_ record: WalkRecord, to members: inout [Member]) {
        if let fromIndex = members.firstIndex(where: { $0.uuid == record.who }) {
            members[fromIndex].debtMinor = Money.add(members[fromIndex].debtMinor, record.paidMinor)
            members[fromIndex].recordCount += 1
        }
        if let toId = record.forWhom.first,
           let toIndex = members.firstIndex(where: { $0.uuid == toId }) {
            members[toIndex].debtMinor = Money.add(members[toIndex].debtMinor, Money.negate(record.paidMinor))
            members[toIndex].recordCount += 1
        }
    }

    private func settlementSuggestions(for group: WalkGroup) -> [SettlementTransfer] {
        var receivers = group.allMembers
            .filter { Money.compare($0.debtMinor, "0") != .orderedAscending }
            .sorted { Money.compare($0.debtMinor, $1.debtMinor) == .orderedDescending }
        var payers = group.allMembers
            .filter { Money.compare($0.debtMinor, "0") == .orderedAscending }
            .map { member -> Member in
                var next = member
                next.debtMinor = Money.negate(member.debtMinor)
                return next
            }
            .sorted { Money.compare($0.debtMinor, $1.debtMinor) == .orderedDescending }

        var result: [SettlementTransfer] = []
        for receiverIndex in receivers.indices {
            while !Money.isZero(receivers[receiverIndex].debtMinor) {
                var advanced = false
                for payerIndex in payers.indices where !Money.isZero(payers[payerIndex].debtMinor) {
                    advanced = true
                    let amount: MoneyMinor
                    if Money.compare(receivers[receiverIndex].debtMinor, payers[payerIndex].debtMinor) != .orderedAscending {
                        amount = payers[payerIndex].debtMinor
                        receivers[receiverIndex].debtMinor = Money.add(receivers[receiverIndex].debtMinor, Money.negate(payers[payerIndex].debtMinor))
                        payers[payerIndex].debtMinor = "0"
                    } else {
                        amount = receivers[receiverIndex].debtMinor
                        payers[payerIndex].debtMinor = Money.add(payers[payerIndex].debtMinor, Money.negate(receivers[receiverIndex].debtMinor))
                        receivers[receiverIndex].debtMinor = "0"
                    }
                    result.append(SettlementTransfer(fromId: payers[payerIndex].uuid, toId: receivers[receiverIndex].uuid, amountMinor: amount))
                    if Money.isZero(receivers[receiverIndex].debtMinor) {
                        break
                    }
                }
                if !advanced {
                    break
                }
            }
        }
        return result
    }

    private static func localGroupId() -> String {
        "l-\(shortIdentifier())"
    }

    private static func localMemberId() -> String {
        "lm-\(shortIdentifier())"
    }

    private static func localRecordId() -> String {
        "lr-\(shortIdentifier())"
    }

    private static func shortIdentifier() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(7)).lowercased()
    }
}
