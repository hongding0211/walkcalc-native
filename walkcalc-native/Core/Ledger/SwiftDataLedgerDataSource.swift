import Foundation
import SwiftData

final class SwiftDataLedgerDataSource: LedgerDataSource {
    let sourceKind = LedgerSourceKind.local

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    static func production() -> SwiftDataLedgerDataSource? {
        do {
            let container = try ModelContainer(for: Self.schema)
            return SwiftDataLedgerDataSource(container: container)
        } catch {
            return nil
        }
    }

    static func inMemory() throws -> SwiftDataLedgerDataSource {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return SwiftDataLedgerDataSource(container: container)
    }

    static func temporaryPersistentStore(url: URL) throws -> SwiftDataLedgerDataSource {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return SwiftDataLedgerDataSource(container: container)
    }

    static var schema: Schema {
        Schema([
            LocalLedgerGroupModel.self,
            LocalLedgerParticipantModel.self,
            LocalLedgerRecordModel.self
        ])
    }

    func home(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerHomeSnapshot> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            let groups = try fetchGroups(modelContext)
            let filtered = filteredGroups(groups, search: search)
            let slice = pageSlice(filtered, page: page, pageSize: pageSize)
            return .success(LedgerHomeSnapshot(
                groups: slice.items.map(projectGroup),
                groupPagination: Pagination(page: page, size: pageSize, total: filtered.count),
                totalBalanceMinor: totalBalance(groups: groups, ownerId: context.localOwner?.uuid),
                source: .local(),
                refreshedToken: nil
            ))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func groups(page: Int, pageSize: Int, search: String?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkGroup>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            let groups = filteredGroups(try fetchGroups(modelContext), search: search)
            let slice = pageSlice(groups, page: page, pageSize: pageSize)
            return .success(LedgerPage(
                items: slice.items.map(projectGroup),
                pagination: Pagination(page: page, size: pageSize, total: groups.count),
                source: .local(),
                refreshedToken: nil
            ))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func groupDetail(groupId: String, recordPageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerGroupSnapshot> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext) else { return .failure(.sourceUnavailable()) }
            let records = sortedRecords(group.records)
            let slice = pageSlice(records, page: 1, pageSize: recordPageSize)
            return .success(LedgerGroupSnapshot(
                group: projectGroup(group),
                records: slice.items.map(projectRecord),
                recordPagination: Pagination(page: 1, size: recordPageSize, total: records.count),
                source: .local(id: groupId),
                refreshedToken: nil
            ))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func groupBalances(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[Member]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext) else { return .failure(.sourceUnavailable()) }
            recomputeBalances(group, updateModifiedAt: false)
            try modelContext.save()
            return .success(mutation(projectMembers(group), source: .local(id: groupId)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func records(groupId: String, page: Int, pageSize: Int, search: RecordSearchRequest?, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerPage<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext) else { return .failure(.sourceUnavailable()) }
            let filtered = sortedRecords(group.records).filter { record in
                guard let search else { return true }
                return search.conditions.contains { conditionMatches(record: record, condition: $0) }
            }
            let slice = pageSlice(filtered, page: page, pageSize: pageSize)
            return .success(LedgerPage(
                items: slice.items.map(projectRecord),
                pagination: Pagination(page: page, size: pageSize, total: filtered.count),
                source: .local(id: groupId),
                refreshedToken: nil
            ))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func memberRecords(groupId: String, memberId: String, page: Int, pageSize: Int, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMemberRecordSnapshot> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext) else { return .failure(.sourceUnavailable()) }
            let records = sortedRecords(group.records).filter { $0.who == memberId || $0.forWhom.contains(memberId) }
            let slice = pageSlice(records, page: page, pageSize: pageSize)
            return .success(LedgerMemberRecordSnapshot(
                member: projectMembers(group).first { $0.uuid == memberId },
                records: slice.items.map(projectRecord),
                pagination: Pagination(page: page, size: pageSize, total: records.count),
                source: .local(id: groupId),
                refreshedToken: nil
            ))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func settlementSuggestion(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[SettlementTransfer]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext) else { return .failure(.sourceUnavailable()) }
            recomputeBalances(group, updateModifiedAt: false)
            try modelContext.save()
            return .success(mutation(settlementSuggestions(for: projectGroup(group)), source: .local(id: groupId)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func createGroup(name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        let now = currentTimestamp()
        let owner = context.localOwner ?? Member(uuid: "local-user-device", name: "Me", avatar: "", debtMinor: "0", costMinor: "0")
        let groupId = Self.localGroupId()
        let group = LocalLedgerGroupModel(id: groupId, name: name, createdAt: now, modifiedAt: now, ownerUserId: owner.uuid)
        let ownerModel = LocalLedgerParticipantModel(
            id: owner.uuid,
            name: owner.name,
            avatar: owner.avatar,
            isTemporary: false,
            createdAt: now,
            modifiedAt: now
        )
        ownerModel.group = group
        group.participants = [ownerModel]
        modelContext.insert(group)
        do {
            try modelContext.save()
            return .success(mutation(groupId, source: .local(id: groupId)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func joinGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        .failure(.authenticationRequired())
    }

    func archiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await updateGroup(code, context: context) { group in
            let ownerId = context.localOwner?.uuid ?? group.ownerUserId
            var archived = group.archivedUserIds
            if !archived.contains(ownerId) {
                archived.append(ownerId)
                group.archivedUserIds = archived
            }
        }
    }

    func unarchiveGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await updateGroup(code, context: context) { group in
            let ownerId = context.localOwner?.uuid ?? group.ownerUserId
            group.archivedUserIds = group.archivedUserIds.filter { $0 != ownerId }
        }
    }

    func deleteGroup(code: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(code, modelContext) else { return .failure(.sourceUnavailable()) }
            modelContext.delete(group)
            try modelContext.save()
            return .success(mutation(code, source: .local(id: code)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func changeGroupName(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        await updateGroup(code, context: context) { group in
            group.name = name
        }
    }

    func invite(code: String, userIds: [String], context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[String]>> {
        .failure(.authenticationRequired())
    }

    func addTempUser(code: String, name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(code, modelContext) else { return .failure(.sourceUnavailable()) }
            let now = currentTimestamp()
            let id = Self.localMemberId()
            let participant = LocalLedgerParticipantModel(id: id, name: name, isTemporary: true, createdAt: now, modifiedAt: now)
            participant.group = group
            group.participants.append(participant)
            group.modifiedAt = now
            group.isDirty = true
            recomputeBalances(group, updateModifiedAt: false)
            try modelContext.save()
            return .success(mutation(id, source: .local(id: code)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func searchUsers(name: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[UserProfile]>> {
        .failure(.authenticationRequired())
    }

    func addRecord(groupId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        await insertRecord(
            groupId: groupId,
            who: who,
            paidMinor: paidMinor,
            forWhom: forWhom,
            type: type,
            text: text,
            long: long,
            lat: lat,
            occurredAt: occurredAt,
            isDebtResolve: false,
            context: context
        )
    }

    func addSettlementRecord(groupId: String, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        let now = currentTimestamp()
        return await insertRecord(
            groupId: groupId,
            who: fromId,
            paidMinor: amountMinor,
            forWhom: [toId],
            type: transferCategory.id,
            text: note,
            long: "",
            lat: "",
            occurredAt: now,
            isDebtResolve: true,
            context: context
        )
    }

    func updateRecord(groupId: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, occurredAt: TimeInterval, isSettlement: Bool, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext),
                  let record = group.records.first(where: { $0.id == recordId }) else {
                return .failure(.sourceUnavailable())
            }
            let now = currentTimestamp()
            record.who = who
            record.paidMinor = paidMinor
            record.forWhom = forWhom
            record.type = type
            record.text = text
            record.occurredAt = occurredAt
            record.isDebtResolve = isSettlement
            record.modifiedAt = now
            record.modifiedBy = context.localOwner?.uuid
            record.isDirty = true
            recomputeBalances(group, updateModifiedAt: true)
            try modelContext.save()
            return .success(mutation(projectRecord(record), source: .local(id: groupId)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func deleteRecord(groupId: String, recordId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext),
                  let record = group.records.first(where: { $0.id == recordId }) else {
                return .failure(.sourceUnavailable())
            }
            modelContext.delete(record)
            group.records.removeAll { $0.id == recordId }
            recomputeBalances(group, updateModifiedAt: true)
            try modelContext.save()
            return .success(mutation(recordId, source: .local(id: groupId)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    func resolveDebts(groupId: String, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<[WalkRecord]>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext) else { return .failure(.sourceUnavailable()) }
            recomputeBalances(group, updateModifiedAt: false)
            let transfers = settlementSuggestions(for: projectGroup(group))
            var created: [WalkRecord] = []
            for transfer in transfers {
                let record = makeRecord(
                    who: transfer.fromId,
                    paidMinor: transfer.amountMinor,
                    forWhom: [transfer.toId],
                    type: transferCategory.id,
                    text: "resolve",
                    long: "",
                    lat: "",
                    occurredAt: currentTimestamp(),
                    isDebtResolve: true,
                    context: context
                )
                record.group = group
                group.records.append(record)
                modelContext.insert(record)
                created.append(projectRecord(record))
            }
            recomputeBalances(group, updateModifiedAt: true)
            try modelContext.save()
            return .success(mutation(created, source: .local(id: groupId)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    private func insertRecord(groupId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, isDebtResolve: Bool, context: LedgerSessionContext) async -> LedgerOperationResult<LedgerMutationResponse<WalkRecord>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        guard !forWhom.isEmpty else {
            return .failure(LedgerOperationFailure(kind: .validation, message: L("Select at least one people."), statusCode: nil, errorData: nil))
        }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(groupId, modelContext) else { return .failure(.sourceUnavailable()) }
            let record = makeRecord(
                who: who,
                paidMinor: paidMinor,
                forWhom: forWhom,
                type: type,
                text: text,
                long: long,
                lat: lat,
                occurredAt: occurredAt,
                isDebtResolve: isDebtResolve,
                context: context
            )
            record.group = group
            group.records.append(record)
            modelContext.insert(record)
            recomputeBalances(group, updateModifiedAt: true)
            try modelContext.save()
            return .success(mutation(projectRecord(record), source: .local(id: groupId)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    private func updateGroup(_ code: String, context: LedgerSessionContext, mutate: (LocalLedgerGroupModel) -> Void) async -> LedgerOperationResult<LedgerMutationResponse<String>> {
        guard isAvailable(context) else { return .failure(.sourceUnavailable()) }
        let modelContext = ModelContext(container)
        do {
            guard let group = try fetchGroup(code, modelContext) else { return .failure(.sourceUnavailable()) }
            mutate(group)
            group.modifiedAt = currentTimestamp()
            group.isDirty = true
            try modelContext.save()
            return .success(mutation(code, source: .local(id: code)))
        } catch {
            return .failure(persistenceFailure(error))
        }
    }

    private func makeRecord(who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, long: String, lat: String, occurredAt: TimeInterval, isDebtResolve: Bool, context: LedgerSessionContext) -> LocalLedgerRecordModel {
        let now = currentTimestamp()
        return LocalLedgerRecordModel(
            id: Self.localRecordId(),
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
            isDebtResolve: isDebtResolve,
            createdBy: context.localOwner?.uuid,
            modifiedBy: context.localOwner?.uuid
        )
    }

    private func fetchGroups(_ context: ModelContext) throws -> [LocalLedgerGroupModel] {
        var descriptor = FetchDescriptor<LocalLedgerGroupModel>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
    }

    private func fetchGroup(_ id: String, _ context: ModelContext) throws -> LocalLedgerGroupModel? {
        try fetchGroups(context).first { $0.id == id }
    }

    private func filteredGroups(_ groups: [LocalLedgerGroupModel], search: String?) -> [LocalLedgerGroupModel] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }

    private func sortedRecords(_ records: [LocalLedgerRecordModel]) -> [LocalLedgerRecordModel] {
        records.sorted {
            if $0.occurredAt == $1.occurredAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.occurredAt > $1.occurredAt
        }
    }

    private func sortedParticipants(_ participants: [LocalLedgerParticipantModel]) -> [LocalLedgerParticipantModel] {
        participants.sorted {
            if $0.isTemporary != $1.isTemporary {
                return !$0.isTemporary
            }
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private func pageSlice<Value>(_ values: [Value], page: Int, pageSize: Int) -> (items: [Value], total: Int) {
        let safePageSize = max(1, pageSize)
        let start = max(0, (max(1, page) - 1) * safePageSize)
        guard start < values.count else { return ([], values.count) }
        let end = min(values.count, start + safePageSize)
        return (Array(values[start..<end]), values.count)
    }

    private func projectGroup(_ group: LocalLedgerGroupModel) -> WalkGroup {
        let members = projectMembers(group)
        let regular = members.filter { !$0.isTemporary }
        let temporary = members.filter(\.isTemporary)
        let ownerId = group.ownerUserId
        let ownerBalance = members.first { $0.uuid == ownerId }?.debtMinor ?? "0"
        let ownerCost = members.first { $0.uuid == ownerId }?.costMinor ?? "0"
        let ownerRecordCount = members.first { $0.uuid == ownerId }?.recordCount ?? 0
        return WalkGroup(
            id: group.id,
            name: group.name,
            createdAt: group.createdAt,
            modifiedAt: group.modifiedAt,
            membersInfo: regular,
            tempUsers: temporary,
            archivedUsers: group.archivedUserIds,
            ownerUserId: ownerId,
            isOwner: true,
            hasCurrentUserBalanceSummary: true,
            currentUserBalanceMinor: ownerBalance,
            currentUserExpenseShareMinor: ownerCost,
            currentUserPaidTotalMinor: "0",
            currentUserRecordCount: ownerRecordCount,
            participantCount: members.count,
            participantPreview: Array(members.prefix(4)),
            serverHasUnresolvedBalance: members.contains { !Money.isZero($0.debtMinor) }
        )
    }

    private func projectMembers(_ group: LocalLedgerGroupModel) -> [Member] {
        sortedParticipants(group.participants).map { participant in
            Member(
                uuid: participant.id,
                name: participant.name,
                avatar: participant.avatar,
                debtMinor: participant.debtMinor,
                costMinor: participant.costMinor,
                recordCount: participant.recordCount,
                isTemporary: participant.isTemporary
            )
        }
    }

    private func projectRecord(_ record: LocalLedgerRecordModel) -> WalkRecord {
        WalkRecord(
            recordId: record.id,
            who: record.who,
            paidMinor: record.paidMinor,
            forWhom: record.forWhom,
            type: record.type,
            text: record.text,
            long: record.long,
            lat: record.lat,
            createdAt: record.createdAt,
            occurredAt: record.occurredAt,
            modifiedAt: record.modifiedAt,
            isDebtResolve: record.isDebtResolve,
            createdBy: record.createdBy,
            modifiedBy: record.modifiedBy
        )
    }

    private func recomputeBalances(_ group: LocalLedgerGroupModel, updateModifiedAt: Bool) {
        for participant in group.participants {
            participant.debtMinor = "0"
            participant.costMinor = "0"
            participant.recordCount = 0
        }

        for record in group.records {
            if record.isDebtResolve {
                applySettlement(record, participants: group.participants)
            } else {
                applyExpense(record, participants: group.participants)
            }
        }

        if updateModifiedAt {
            group.modifiedAt = currentTimestamp()
            group.isDirty = true
        }
    }

    private func applyExpense(_ record: LocalLedgerRecordModel, participants: [LocalLedgerParticipantModel]) {
        guard !record.forWhom.isEmpty else { return }
        if let payer = participants.first(where: { $0.id == record.who }) {
            payer.debtMinor = Money.add(payer.debtMinor, record.paidMinor)
            payer.recordCount += 1
        }
        let share = Money.splitFirst(record.paidMinor, count: record.forWhom.count)
        for participantId in record.forWhom {
            guard let participant = participants.first(where: { $0.id == participantId }) else { continue }
            participant.debtMinor = Money.add(participant.debtMinor, Money.negate(share))
            participant.costMinor = Money.add(participant.costMinor, share)
            if participantId != record.who {
                participant.recordCount += 1
            }
        }
    }

    private func applySettlement(_ record: LocalLedgerRecordModel, participants: [LocalLedgerParticipantModel]) {
        if let from = participants.first(where: { $0.id == record.who }) {
            from.debtMinor = Money.add(from.debtMinor, record.paidMinor)
            from.recordCount += 1
        }
        if let toId = record.forWhom.first,
           let to = participants.first(where: { $0.id == toId }) {
            to.debtMinor = Money.add(to.debtMinor, Money.negate(record.paidMinor))
            to.recordCount += 1
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

    private func conditionMatches(record: LocalLedgerRecordModel, condition: RecordSearchCondition) -> Bool {
        switch condition.field {
        case "note":
            return record.text.localizedCaseInsensitiveContains(condition.query)
        case "categoryName":
            return L(expenseCategory(for: record.type).titleKey).localizedCaseInsensitiveContains(condition.query)
        default:
            return false
        }
    }

    private func totalBalance(groups: [LocalLedgerGroupModel], ownerId: String?) -> MoneyMinor {
        guard let ownerId else { return "0" }
        return groups.reduce("0") { total, group in
            let balance = group.participants.first { $0.id == ownerId }?.debtMinor ?? "0"
            return Money.add(total, balance)
        }
    }

    private func mutation<Value>(_ value: Value?, source: LedgerSourceMetadata) -> LedgerMutationResponse<Value> {
        LedgerMutationResponse(value: value, message: nil, errorData: nil, source: source, refreshedToken: nil)
    }

    private func isAvailable(_ context: LedgerSessionContext) -> Bool {
        context.localSourceAvailable
    }

    private func persistenceFailure(_ error: Error) -> LedgerOperationFailure {
        LedgerOperationFailure(kind: .recoverableNetwork, message: error.localizedDescription, statusCode: nil, errorData: nil)
    }

    private func currentTimestamp() -> TimeInterval {
        Date().timeIntervalSince1970 * 1000
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
