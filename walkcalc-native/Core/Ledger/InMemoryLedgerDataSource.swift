import Foundation

final class InMemoryLedgerDataSource: LedgerDataSource {
    let sourceKind = LedgerSourceKind.local

    private var groups: [WalkGroup]
    private var recordsByGroup: [String: [WalkRecord]]
    private var removedMembersByGroup: [String: [Member]] = [:]

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
            currencyBalances: currencyBalances(ownerId: context.localOwner?.uuid),
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

    func settlementSuggestion(groupId: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[SettlementTransfer]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
        return .success(mutation(settlementSuggestions(for: group, currencyCode: currencyCode), source: .local(id: groupId)))
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
        let previousCurrencyCode = groups[index].currencyCode
        recordsByGroup[code] = recordsByGroup[code]?.map { record in
            var next = record
            if next.currencyCode == nil {
                next.currencyCode = previousCurrencyCode
            }
            return next
        }
        groups[index].currencyCode = CurrencyCatalog.normalizedCode(currencyCode)
        recomputeBalances(groupId: code)
        return .success(mutation(groups[index].currencyCode, source: .local(id: code)))
    }

    func invite(code: String, userIds: [String], context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[String]>> {
        .failure(.authenticationRequired())
    }

    func addTempUser(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = groups.firstIndex(where: { $0.id == code }) else { return .failure(.sourceUnavailable()) }
        let restored = removedMembersByGroup[code]?.first { $0.isTemporary && $0.name == name }
        let id = restored?.uuid ?? Self.localMemberId()
        if let restored {
            groups[index].tempUsers.append(restored)
            groups[index].historicalMembers.removeAll { $0.uuid == restored.uuid }
            removedMembersByGroup[code]?.removeAll { $0.uuid == restored.uuid }
        } else {
            groups[index].tempUsers.append(Member(uuid: id, name: name, avatar: "", debtMinor: "0", costMinor: "0", isTemporary: true))
        }
        recomputeBalances(groupId: code)
        groups[index].participantCount = groups[index].allMembers.count
        groups[index].participantPreview = Array(groups[index].allMembers.prefix(4))
        return .success(mutation(id, source: .local(id: code)))
    }

    func removeMember(code: String, participantId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context),
              let index = groups.firstIndex(where: { $0.id == code }),
              groups[index].isOwner,
              participantId != groups[index].ownerUserId,
              let member = groups[index].allMembers.first(where: { $0.uuid == participantId }),
              !member.hasUnresolvedCurrencyBalance else {
            return .failure(.sourceUnavailable())
        }
        removedMembersByGroup[code, default: []].append(member)
        groups[index].historicalMembers.append(member)
        groups[index].membersInfo.removeAll { $0.uuid == participantId }
        groups[index].tempUsers.removeAll { $0.uuid == participantId }
        recomputeBalances(groupId: code)
        return .success(mutation(participantId, source: .local(id: code)))
    }

    func searchUsers(name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[UserProfile]>> {
        .failure(.authenticationRequired())
    }

    func addRecord(groupId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
        let memberIds = Set(group.allMembers.map(\.uuid))
        guard memberIds.contains(who), forWhom.allSatisfy(memberIds.contains) else { return .failure(.sourceUnavailable()) }
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
            modifiedBy: context.localOwner?.uuid,
            currencyCode: CurrencyCatalog.normalizedCode(currencyCode ?? group.currencyCode)
        )
        recordsByGroup[groupId, default: []].insert(record, at: 0)
        recomputeBalances(groupId: groupId)
        return .success(mutation(record, source: .local(id: groupId)))
    }

    func addSettlementRecord(groupId: String, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let now = Date().timeIntervalSince1970 * 1000
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
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
            modifiedBy: context.localOwner?.uuid,
            currencyCode: CurrencyCatalog.normalizedCode(currencyCode ?? group.currencyCode)
        )
        recordsByGroup[groupId, default: []].insert(record, at: 0)
        recomputeBalances(groupId: groupId)
        return .success(mutation(record, source: .local(id: groupId)))
    }

    func updateRecord(groupId: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let index = recordsByGroup[groupId]?.firstIndex(where: { $0.recordId == recordId }) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId), recordCanMutate(recordsByGroup[groupId]![index], in: group) else { return .failure(.sourceUnavailable()) }
        let memberIds = Set(group.allMembers.map(\.uuid))
        guard memberIds.contains(who), forWhom.allSatisfy(memberIds.contains) else { return .failure(.sourceUnavailable()) }
        recordsByGroup[groupId]?[index].who = who
        recordsByGroup[groupId]?[index].paidMinor = paidMinor
        recordsByGroup[groupId]?[index].forWhom = forWhom
        recordsByGroup[groupId]?[index].type = type
        recordsByGroup[groupId]?[index].text = text
        recordsByGroup[groupId]?[index].occurredAt = occurredAt
        recordsByGroup[groupId]?[index].isDebtResolve = isSettlement
        recordsByGroup[groupId]?[index].currencyCode = CurrencyCatalog.normalizedCode(
            currencyCode ?? recordsByGroup[groupId]?[index].currencyCode ?? group.currencyCode
        )
        recordsByGroup[groupId]?[index].modifiedAt = Date().timeIntervalSince1970 * 1000
        recomputeBalances(groupId: groupId)
        return .success(mutation(recordsByGroup[groupId]?[index], source: .local(id: groupId)))
    }

    func deleteRecord(groupId: String, recordId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId),
              let record = recordsByGroup[groupId]?.first(where: { $0.recordId == recordId }),
              recordCanMutate(record, in: group) else { return .failure(.sourceUnavailable()) }
        recordsByGroup[groupId]?.removeAll { $0.recordId == recordId }
        recomputeBalances(groupId: groupId)
        return .success(mutation(recordId, source: .local(id: groupId)))
    }

    private func recordCanMutate(_ record: WalkRecord, in group: WalkGroup) -> Bool {
        let memberIds = Set(group.allMembers.map(\.uuid))
        return memberIds.contains(record.who) && record.forWhom.allSatisfy(memberIds.contains)
    }

    func resolveDebts(groupId: String, currencyCode: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[WalkRecord]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard let group = group(id: groupId) else { return .failure(.sourceUnavailable()) }
        var created: [WalkRecord] = []
        let resolvedCurrencyCode = CurrencyCatalog.normalizedCode(currencyCode ?? group.currencyCode)
        for transfer in settlementSuggestions(for: group, currencyCode: resolvedCurrencyCode) {
            if case .success(let response) = await addSettlementRecord(groupId: groupId, fromId: transfer.fromId, toId: transfer.toId, amountMinor: transfer.amountMinor, note: "resolve", currencyCode: resolvedCurrencyCode, context: context),
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

    private func currencyBalances(ownerId: String?) -> [CurrencyBalanceSummary] {
        guard let ownerId else { return [] }
        let totals = groups.reduce(into: [String: MoneyMinor]()) { result, group in
            guard !group.archivedUsers.contains(ownerId) else { return }
            guard let member = group.allMembers.first(where: { $0.uuid == ownerId }) else { return }
            if member.currencyBalances.isEmpty {
                let currencyCode = CurrencyCatalog.normalizedCode(group.currencyCode)
                result[currencyCode] = Money.add(result[currencyCode] ?? "0", member.debtMinor)
            } else {
                for balance in member.currencyBalances {
                    let currencyCode = CurrencyCatalog.normalizedCode(balance.currencyCode)
                    result[currencyCode] = Money.add(result[currencyCode] ?? "0", balance.debtMinor)
                }
            }
        }
        return totals.keys.sorted().map { currencyCode in
            CurrencyBalanceSummary(
                currencyCode: currencyCode,
                totalBalanceMinor: totals[currencyCode] ?? "0"
            )
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
            members[index].currencyBalances = []
        }

        for record in records {
            if record.isDebtResolve {
                applySettlement(record, groupCurrencyCode: groups[groupIndex].currencyCode, to: &members)
            } else {
                applyExpense(record, groupCurrencyCode: groups[groupIndex].currencyCode, to: &members)
            }
        }

        groups[groupIndex].membersInfo = members.filter { !$0.isTemporary }
        groups[groupIndex].tempUsers = members.filter(\.isTemporary)
        groups[groupIndex].participantCount = members.count
        groups[groupIndex].participantPreview = Array(members.prefix(4))
        groups[groupIndex].modifiedAt = Date().timeIntervalSince1970 * 1000
    }

    private func applyExpense(_ record: WalkRecord, groupCurrencyCode: String, to members: inout [Member]) {
        guard !record.forWhom.isEmpty else { return }
        let currencyCode = CurrencyCatalog.normalizedCode(record.currencyCode ?? groupCurrencyCode)
        if let payerIndex = members.firstIndex(where: { $0.uuid == record.who }) {
            members[payerIndex].debtMinor = Money.add(members[payerIndex].debtMinor, record.paidMinor)
            members[payerIndex].recordCount += 1
            applyCurrencyDelta(
                to: &members[payerIndex],
                currencyCode: currencyCode,
                debtMinor: record.paidMinor,
                paidTotalMinor: record.paidMinor,
                recordCount: 1
            )
        }
        let share = Money.splitFirst(record.paidMinor, count: record.forWhom.count)
        for participantId in record.forWhom {
            guard let index = members.firstIndex(where: { $0.uuid == participantId }) else { continue }
            members[index].debtMinor = Money.add(members[index].debtMinor, Money.negate(share))
            members[index].costMinor = Money.add(members[index].costMinor, share)
            if participantId != record.who {
                members[index].recordCount += 1
            }
            applyCurrencyDelta(
                to: &members[index],
                currencyCode: currencyCode,
                debtMinor: Money.negate(share),
                costMinor: share,
                recordCount: participantId == record.who ? 0 : 1
            )
        }
    }

    private func applySettlement(_ record: WalkRecord, groupCurrencyCode: String, to members: inout [Member]) {
        let currencyCode = CurrencyCatalog.normalizedCode(record.currencyCode ?? groupCurrencyCode)
        if let fromIndex = members.firstIndex(where: { $0.uuid == record.who }) {
            members[fromIndex].debtMinor = Money.add(members[fromIndex].debtMinor, record.paidMinor)
            members[fromIndex].recordCount += 1
            applyCurrencyDelta(
                to: &members[fromIndex],
                currencyCode: currencyCode,
                debtMinor: record.paidMinor,
                recordCount: 1,
                settlementOutMinor: record.paidMinor
            )
        }
        if let toId = record.forWhom.first,
           let toIndex = members.firstIndex(where: { $0.uuid == toId }) {
            members[toIndex].debtMinor = Money.add(members[toIndex].debtMinor, Money.negate(record.paidMinor))
            members[toIndex].recordCount += 1
            applyCurrencyDelta(
                to: &members[toIndex],
                currencyCode: currencyCode,
                debtMinor: Money.negate(record.paidMinor),
                recordCount: 1,
                settlementInMinor: record.paidMinor
            )
        }
    }

    private func settlementSuggestions(for group: WalkGroup, currencyCode: String?) -> [SettlementTransfer] {
        let resolvedCurrencyCode = CurrencyCatalog.normalizedCode(currencyCode ?? group.currencyCode)
        let currencyMembers = group.allMembers.map { member -> Member in
            var next = member
            if let balance = member.currencyBalances.first(where: { $0.currencyCode == resolvedCurrencyCode }) {
                next.debtMinor = balance.debtMinor
            } else if resolvedCurrencyCode != CurrencyCatalog.normalizedCode(group.currencyCode) || !member.currencyBalances.isEmpty {
                next.debtMinor = "0"
            }
            return next
        }
        var receivers = currencyMembers
            .filter { Money.compare($0.debtMinor, "0") != .orderedAscending }
            .sorted { Money.compare($0.debtMinor, $1.debtMinor) == .orderedDescending }
        var payers = currencyMembers
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
                    result.append(SettlementTransfer(fromId: payers[payerIndex].uuid, toId: receivers[receiverIndex].uuid, amountMinor: amount, currencyCode: resolvedCurrencyCode))
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

    private func applyCurrencyDelta(
        to member: inout Member,
        currencyCode: String,
        debtMinor: MoneyMinor = "0",
        costMinor: MoneyMinor = "0",
        paidTotalMinor: MoneyMinor = "0",
        recordCount: Int = 0,
        settlementInMinor: MoneyMinor = "0",
        settlementOutMinor: MoneyMinor = "0"
    ) {
        let normalized = CurrencyCatalog.normalizedCode(currencyCode)
        if !member.currencyBalances.contains(where: { $0.currencyCode == normalized }) {
            member.currencyBalances.append(MemberCurrencyProjection(
                currencyCode: normalized,
                debtMinor: "0",
                costMinor: "0",
                paidTotalMinor: "0",
                recordCount: 0,
                settlementInMinor: "0",
                settlementOutMinor: "0"
            ))
        }
        guard let index = member.currencyBalances.firstIndex(where: { $0.currencyCode == normalized }) else { return }
        member.currencyBalances[index].debtMinor = Money.add(member.currencyBalances[index].debtMinor, debtMinor)
        member.currencyBalances[index].costMinor = Money.add(member.currencyBalances[index].costMinor, costMinor)
        member.currencyBalances[index].paidTotalMinor = Money.add(member.currencyBalances[index].paidTotalMinor, paidTotalMinor)
        member.currencyBalances[index].recordCount += recordCount
        member.currencyBalances[index].settlementInMinor = Money.add(member.currencyBalances[index].settlementInMinor, settlementInMinor)
        member.currencyBalances[index].settlementOutMinor = Money.add(member.currencyBalances[index].settlementOutMinor, settlementOutMinor)
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
