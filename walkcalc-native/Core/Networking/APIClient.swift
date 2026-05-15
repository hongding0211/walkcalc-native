import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case patch = "PATCH"
}

struct APIClient: Sendable {
    #if DEBUG
    var baseURL = URL(string: ProcessInfo.processInfo.environment["WALKCALC_API_BASE_URL"] ?? "http://127.0.0.1:3500")!
    var webBaseURL = URL(string: ProcessInfo.processInfo.environment["HONG97_WEB_BASE_URL"] ?? "http://127.0.0.1:3000")!
    #else
    var baseURL = URL(string: ProcessInfo.processInfo.environment["WALKCALC_API_BASE_URL"] ?? "https://hong97.ltd/api")!
    var webBaseURL = URL(string: ProcessInfo.processInfo.environment["HONG97_WEB_BASE_URL"] ?? "https://hong97.ltd")!
    #endif

    func loginURL() -> URL {
        let redirect = webBaseURL.appendingPathComponent("auth/callback").absoluteString
        var components = URLComponents(url: webBaseURL.appendingPathComponent("sso/login"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "hideNavbar", value: "1")
        ]
        return components.url!
    }

    func profileURL() -> URL {
        var components = URLComponents(url: webBaseURL.appendingPathComponent("sso/profile"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "hideNavbar", value: "1")]
        return components.url!
    }

    func redirectPrefix() -> String {
        webBaseURL.appendingPathComponent("auth/callback").absoluteString
    }

    func userInfo(token: String) async throws -> APIEnvelope<UserProfile> {
        try await request(.get, path: "/walkcalc/users/me", token: token, mapper: mapUser)
    }

    func homeSummary(token: String) async throws -> APIEnvelope<MoneyMinor> {
        try await request(.get, path: "/walkcalc/home/summary", token: token) { raw in
            Money.minorFromDecimalString(dictPayload(raw)["totalBalance"])
        }
    }

    func updateProfileMetadata(token: String, metadata: [String: Any]) async throws -> APIEnvelope<[String: Any]> {
        try await request(.patch, path: "/auth/profile", token: token, body: ["metadata": metadata]) { raw in
            dictPayload(raw)
        }
    }

    func groups(page: Int, pageSize: Int, search: String? = nil, token: String) async throws -> APIEnvelope<[WalkGroup]> {
        var query = [
            "page": "\(page)",
            "pageSize": "\(pageSize)"
        ]
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query["search"] = search
        }
        return try await request(.get, path: "/walkcalc/groups/my", query: query, token: token) { raw in
            arrayPayload(raw).map(mapGroup)
        }
    }

    func group(code: String, token: String) async throws -> APIEnvelope<WalkGroup> {
        try await request(.get, path: "/walkcalc/groups/\(code)", token: token, mapper: mapGroup)
    }

    func groupBalances(groupCode: String, token: String) async throws -> APIEnvelope<[Member]> {
        try await request(.get, path: "/walkcalc/groups/\(groupCode)/balances", token: token) { raw in
            mapParticipants(dictPayload(raw)["participants"])
        }
    }

    func createGroup(name: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/groups", token: token, body: ["name": name]) { raw in
            dictPayload(raw)["code"] as? String ?? ""
        }
    }

    func joinGroup(code: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/groups/join", token: token, body: ["code": code]) { raw in
            dictPayload(raw)["code"] as? String ?? ""
        }
    }

    func archiveGroup(code: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/groups/\(code)/archive", token: token) { raw in
            dictPayload(raw)["code"] as? String ?? code
        }
    }

    func unarchiveGroup(code: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/groups/\(code)/unarchive", token: token) { raw in
            dictPayload(raw)["code"] as? String ?? code
        }
    }

    func deleteGroup(code: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.delete, path: "/walkcalc/groups/\(code)", token: token) { raw in
            dictPayload(raw)["code"] as? String ?? code
        }
    }

    func changeGroupName(code: String, name: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.patch, path: "/walkcalc/groups/\(code)/name", token: token, body: ["name": name]) { raw in
            dictPayload(raw)["name"] as? String ?? name
        }
    }

    func invite(code: String, userIds: [String], token: String) async throws -> APIEnvelope<[String]> {
        try await request(.post, path: "/walkcalc/groups/\(code)/invite", token: token, body: ["userIds": userIds]) { raw in
            dictPayload(raw)["userIds"] as? [String] ?? userIds
        }
    }

    func addTempUser(code: String, name: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/groups/\(code)/temp-users", token: token, body: ["name": name]) { raw in
            dictPayload(raw)["participantId"] as? String ?? name
        }
    }

    func searchUsers(name: String, token: String) async throws -> APIEnvelope<[UserProfile]> {
        try await request(.get, path: "/walkcalc/users/search", query: ["name": name], token: token) { raw in
            arrayPayload(raw).map(mapUser)
        }
    }

    func records(groupCode: String, page: Int, pageSize: Int, search: String? = nil, recordSearch: RecordSearchRequest? = nil, token: String) async throws -> APIEnvelope<[WalkRecord]> {
        var query = [
            "page": "\(page)",
            "pageSize": "\(pageSize)"
        ]
        if let recordSearch, let encodedSearch = encodedRecordSearch(recordSearch) {
            query["search"] = encodedSearch
        } else if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query["search"] = search
        }
        return try await request(.get, path: "/walkcalc/groups/\(groupCode)/records", query: query, token: token) { raw in
            arrayPayload(raw).map(mapRecord)
        }
    }

    func participantRecords(groupCode: String, participantId: String, page: Int, pageSize: Int, token: String) async throws -> APIEnvelope<MemberRecordPage> {
        try await request(.get, path: "/walkcalc/groups/\(groupCode)/balances/\(participantId)/records", query: [
            "page": "\(page)",
            "pageSize": "\(pageSize)"
        ], token: token) { raw in
            mapMemberRecordPage(raw)
        }
    }

    func record(id: String, token: String) async throws -> APIEnvelope<WalkRecord> {
        try await request(.get, path: "/walkcalc/records/\(id)", token: token, mapper: mapRecord)
    }

    func addRecord(groupCode: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, token: String, long: String = "", lat: String = "", occurredAt: TimeInterval) async throws -> APIEnvelope<WalkRecord> {
        let body = expenseRecordBody(
            groupCode: groupCode,
            payerId: who,
            amountMinor: paidMinor,
            participantIds: forWhom,
            category: type,
            note: text,
            long: long,
            lat: lat,
            occurredAt: occurredAt
        )
        return try await request(.post, path: "/walkcalc/records", token: token, body: body) { raw in
            mapRecord(dictPayload(raw)["record"] ?? raw)
        }
    }

    func addSettlementRecord(groupCode: String, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, token: String) async throws -> APIEnvelope<WalkRecord> {
        let body = settlementRecordBody(groupCode: groupCode, fromId: fromId, toId: toId, amountMinor: amountMinor, note: note, occurredAt: Date().timeIntervalSince1970 * 1000)
        return try await request(.post, path: "/walkcalc/records", token: token, body: body) { raw in
            mapRecord(dictPayload(raw)["record"] ?? raw)
        }
    }

    func updateRecord(groupCode: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, token: String, occurredAt: TimeInterval, isSettlement: Bool = false) async throws -> APIEnvelope<WalkRecord> {
        let body: [String: Any]
        if isSettlement {
            body = settlementRecordBody(groupCode: groupCode, recordId: recordId, fromId: who, toId: forWhom.first ?? "", amountMinor: paidMinor, note: text, occurredAt: occurredAt)
        } else {
            body = expenseRecordBody(groupCode: groupCode, recordId: recordId, payerId: who, amountMinor: paidMinor, participantIds: forWhom, category: type, note: text, occurredAt: occurredAt)
        }
        return try await request(.post, path: "/walkcalc/records/update", token: token, body: body) { raw in
            mapRecord(dictPayload(raw)["record"] ?? raw)
        }
    }

    func dropRecord(groupCode: String, recordId: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/records/drop", token: token, body: ["groupCode": groupCode, "recordId": recordId]) { raw in
            dictPayload(raw)["recordId"] as? String ?? recordId
        }
    }

    func settlementSuggestion(groupCode: String, token: String) async throws -> APIEnvelope<[(fromId: String, toId: String, amountMinor: MoneyMinor)]> {
        try await request(.get, path: "/walkcalc/groups/\(groupCode)/settlement-suggestion", token: token) { raw in
            arrayPayload(dictPayload(raw)["transfers"]).map { transfer in
                (
                    fromId: transfer["fromId"] as? String ?? "",
                    toId: transfer["toId"] as? String ?? "",
                    amountMinor: Money.minorFromDecimalString(transfer["amount"])
                )
            }
        }
    }

    func resolveDebts(groupCode: String, token: String) async throws -> APIEnvelope<[WalkRecord]> {
        try await request(.post, path: "/walkcalc/groups/\(groupCode)/settlements/resolve", token: token, body: [:]) { raw in
            arrayPayload(dictPayload(raw)["records"]).map(mapRecord)
        }
    }

    private func encodedRecordSearch(_ search: RecordSearchRequest) -> String? {
        guard let data = try? JSONEncoder().encode(search) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func request<T>(_ method: HTTPMethod, path: String, query: [String: String] = [:], token: String, body: [String: Any]? = nil, mapper: (Any?) -> T) async throws -> APIEnvelope<T> {
        var response = try await execute(method, path: path, query: query, token: token, body: body)
        var refreshedToken: String?
        if response.status == 401 || response.status == 403 {
            if let nextToken = try? await AuthRefreshCoordinator.shared.refresh({ try await refreshAccessToken() }) {
                refreshedToken = nextToken
                response = try await execute(method, path: path, query: query, token: nextToken, body: body)
            }
        }

        let envelope = response.raw as? [String: Any] ?? [:]
        let success = (envelope["isSuccess"] as? Bool) ?? (envelope["success"] as? Bool) ?? false
        let sourceData = payload(from: envelope)
        return APIEnvelope(
            success: success,
            data: mapper(sourceData),
            pagination: pagination(from: envelope),
            message: envelope["msg"] as? String ?? envelope["message"] as? String,
            errorData: success ? nil : sourceData as? [String: Any],
            refreshedToken: refreshedToken
        )
    }

    private func execute(_ method: HTTPMethod, path: String, query: [String: String], token: String?, body: [String: Any]?) async throws -> (status: Int, raw: Any?) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(L10n.serverLanguageCode, forHTTPHeaderField: "x-locale")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body, method != .get {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
        return (status, json)
    }

    private func refreshAccessToken() async throws -> String? {
        let response = try await execute(.post, path: "/auth/refreshToken", query: [:], token: nil, body: nil)
        guard response.status >= 200, response.status < 300 else {
            return nil
        }
        let envelope = response.raw as? [String: Any] ?? [:]
        let data = payload(from: envelope) as? [String: Any] ?? [:]
        return data["accessToken"] as? String ?? data["token"] as? String
    }
}

private actor AuthRefreshCoordinator {
    static let shared = AuthRefreshCoordinator()

    private var refreshTask: Task<String?, Error>?

    func refresh(_ operation: @escaping @Sendable () async throws -> String?) async throws -> String? {
        if let refreshTask {
            return try await refreshTask.value
        }

        let refreshTask = Task {
            try await operation()
        }
        self.refreshTask = refreshTask

        do {
            let token = try await refreshTask.value
            self.refreshTask = nil
            return token
        } catch {
            self.refreshTask = nil
            throw error
        }
    }
}

private func payload(from envelope: [String: Any]) -> Any? {
    if let data = envelope["data"] as? [String: Any], data["data"] != nil {
        return data["data"]
    }
    return envelope["data"]
}

private func pagination(from envelope: [String: Any]) -> Pagination? {
    guard let data = envelope["data"] as? [String: Any] else {
        return nil
    }
    if let total = data["total"] as? Int {
        return Pagination(page: data["page"] as? Int ?? 1, size: data["pageSize"] as? Int ?? data["size"] as? Int ?? 10, total: total)
    }
    return nil
}

private func dictPayload(_ raw: Any?) -> [String: Any] {
    raw as? [String: Any] ?? [:]
}

private func arrayPayload(_ raw: Any?) -> [[String: Any]] {
    raw as? [[String: Any]] ?? []
}

private func expenseRecordBody(
    groupCode: String,
    recordId: String? = nil,
    payerId: String,
    amountMinor: MoneyMinor,
    participantIds: [String],
    category: String,
    note: String,
    long: String = "",
    lat: String = "",
    occurredAt: TimeInterval
) -> [String: Any] {
    var body: [String: Any] = [
        "groupCode": groupCode,
        "type": "expense",
        "amount": Money.decimalString(fromMinor: amountMinor),
        "payerId": payerId,
        "participantIds": participantIds,
        "category": category,
        "note": note
    ]
    if let recordId {
        body["recordId"] = recordId
    }
    body["occurredAt"] = Int(occurredAt)
    if !long.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        body["long"] = long
    }
    if !lat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        body["lat"] = lat
    }
    return body
}

private func settlementRecordBody(groupCode: String, recordId: String? = nil, fromId: String, toId: String, amountMinor: MoneyMinor, note: String, occurredAt: TimeInterval) -> [String: Any] {
    var body: [String: Any] = [
        "groupCode": groupCode,
        "type": "settlement",
        "amount": Money.decimalString(fromMinor: amountMinor),
        "fromId": fromId,
        "toId": toId,
        "note": note
    ]
    if let recordId {
        body["recordId"] = recordId
    }
    body["occurredAt"] = Int(occurredAt)
    return body
}

private func avatarValue(profile: [String: Any]) -> String {
    profile["avatar"] as? String
        ?? profile["avatarUrl"] as? String
        ?? ""
}

private func mapUser(_ raw: Any?) -> UserProfile {
    let dict = dictPayload(raw)
    let profile = dict["profile"] as? [String: Any] ?? [:]
    let uuid = dict["userId"] as? String ?? ""
    return UserProfile(
        uuid: uuid,
        name: profile["name"] as? String ?? uuid,
        avatar: avatarValue(profile: profile)
    )
}

private func mapMember(_ raw: [String: Any], temporary: Bool = false) -> Member {
    let profile = raw["profile"] as? [String: Any] ?? [:]
    let isTemporary = temporary || raw["kind"] as? String == "tempUser"
    let uuid = raw["participantId"] as? String ?? ""
    let debtMinor = Money.minorFromDecimalString(raw["balance"])
    let costMinor = Money.minorFromDecimalString(raw["expenseShare"])
    return Member(
        uuid: uuid,
        name: profile["name"] as? String ?? raw["tempName"] as? String ?? raw["name"] as? String ?? uuid,
        avatar: avatarValue(profile: profile),
        debtMinor: debtMinor,
        costMinor: costMinor,
        recordCount: raw["recordCount"] as? Int ?? 0,
        isTemporary: isTemporary
    )
}

private func mapParticipants(_ raw: Any?) -> [Member] {
    arrayPayload(raw).map { mapMember($0) }
}

private func mapMemberRecordPage(_ raw: Any?) -> MemberRecordPage {
    let dict = dictPayload(raw)
    return MemberRecordPage(
        member: mapMember(dict),
        records: arrayPayload(dict["records"]).map(mapRecord)
    )
}

private func mapGroup(_ raw: Any?) -> WalkGroup {
    let dict = dictPayload(raw)
    let participants = dict["participants"] as? [[String: Any]] ?? []
    let participantPreview = arrayPayload(dict["participantPreview"]).map { mapMember($0, temporary: ($0["kind"] as? String) == "tempUser") }
    let members: [Member]
    let tempUsers: [Member]
    if participants.isEmpty {
        members = []
        tempUsers = []
    } else {
        members = participants
            .filter { ($0["kind"] as? String ?? "user") == "user" }
            .map { mapMember($0) }
        tempUsers = participants
            .filter { $0["kind"] as? String == "tempUser" }
            .map { mapMember($0, temporary: true) }
    }
    return WalkGroup(
        id: dict["code"] as? String ?? "",
        name: dict["name"] as? String ?? "",
        createdAt: timeInterval(dict["createdAt"]),
        modifiedAt: timeInterval(dict["modifiedAt"]),
        membersInfo: members,
        tempUsers: tempUsers,
        archivedUsers: dict["archivedUserIds"] as? [String] ?? [],
        isOwner: dict["isOwner"] as? Bool ?? false,
        hasCurrentUserBalanceSummary: dict["currentUserBalance"] != nil,
        currentUserBalanceMinor: Money.minorFromDecimalString(dict["currentUserBalance"]),
        currentUserExpenseShareMinor: Money.minorFromDecimalString(dict["currentUserExpenseShare"]),
        currentUserPaidTotalMinor: Money.minorFromDecimalString(dict["currentUserPaidTotal"]),
        currentUserRecordCount: dict["currentUserRecordCount"] as? Int ?? 0,
        participantCount: dict["participantCount"] as? Int ?? participants.count,
        participantPreview: participantPreview,
        serverHasUnresolvedBalance: dict["hasUnresolvedBalance"] as? Bool
    )
}

private func mapRecord(_ raw: Any?) -> WalkRecord {
    let dict = dictPayload(raw)
    let backendType = dict["type"] as? String ?? "expense"
    let isSettlement = backendType == "settlement"
    let category = dict["category"] as? String
    let payerId = dict["payerId"] as? String
    let fromId = dict["fromId"] as? String
    let toId = dict["toId"] as? String
    let participants = dict["participantIds"] as? [String]
    let involved = dict["involvedParticipantIds"] as? [String] ?? []
    return WalkRecord(
        recordId: dict["recordId"] as? String ?? "",
        who: payerId ?? fromId ?? "",
        paidMinor: Money.minorFromDecimalString(dict["amount"]),
        forWhom: participants ?? toId.map { [$0] } ?? involved.filter { $0 != fromId },
        type: isSettlement ? transferCategory.id : category ?? "food",
        text: dict["note"] as? String ?? "",
        long: dict["long"] as? String ?? "",
        lat: dict["lat"] as? String ?? "",
        createdAt: timeInterval(dict["createdAt"]),
        occurredAt: timeInterval(dict["occurredAt"]),
        modifiedAt: timeInterval(dict["updatedAt"]),
        isDebtResolve: isSettlement,
        createdBy: dict["createdBy"] as? String,
        modifiedBy: dict["updatedBy"] as? String
    )
}

private func timeInterval(_ raw: Any?) -> TimeInterval {
    if let value = raw as? TimeInterval {
        return value
    }
    if let int = raw as? Int {
        return TimeInterval(int)
    }
    if let string = raw as? String, let value = TimeInterval(string) {
        return value
    }
    return Date().timeIntervalSince1970 * 1000
}

#if DEBUG
enum LedgerAPIContractVerification {
    static func assertAllCasesPass() {
        let expenseBody = expenseRecordBody(
            groupCode: "AB12",
            payerId: "user_1",
            amountMinor: "10000",
            participantIds: ["user_1", "user_2", "tmp_1"],
            category: "food",
            note: "Dinner",
            long: "121.4737",
            lat: "31.2304",
            occurredAt: 1_710_000_000_000
        )
        assertNoLegacyFields(expenseBody, prefix: "expense-request")
        expect(expenseBody["type"] as? String, equals: "expense", prefix: "expense-request-type")
        expect(expenseBody["amount"] as? String, equals: "100.00", prefix: "expense-request-amount")
        expect(expenseBody["payerId"] as? String, equals: "user_1", prefix: "expense-request-payer")
        expect(expenseBody["participantIds"] as? [String], equals: ["user_1", "user_2", "tmp_1"], prefix: "expense-request-participants")
        expect(expenseBody["category"] as? String, equals: "food", prefix: "expense-request-category")
        expect(expenseBody["createdAt"] as? Int, equals: nil, prefix: "expense-request-no-client-created-at")
        expect(expenseBody["occurredAt"] as? Int, equals: 1_710_000_000_000, prefix: "expense-request-occurred-at")
        expect(expenseBody["long"] as? String, equals: "121.4737", prefix: "expense-request-long")
        expect(expenseBody["lat"] as? String, equals: "31.2304", prefix: "expense-request-lat")

        let updateExpenseBody = expenseRecordBody(
            groupCode: "AB12",
            recordId: "record_1",
            payerId: "user_2",
            amountMinor: "12000",
            participantIds: ["user_2", "tmp_1"],
            category: "traffic",
            note: "Taxi",
            occurredAt: 1_710_000_030_000
        )
        assertNoLegacyFields(updateExpenseBody, prefix: "update-expense-request")
        expect(updateExpenseBody["recordId"] as? String, equals: "record_1", prefix: "update-expense-request-id")
        expect(updateExpenseBody["amount"] as? String, equals: "120.00", prefix: "update-expense-request-amount")
        expect(updateExpenseBody["createdAt"] as? Int, equals: nil, prefix: "update-expense-request-no-client-created-at")
        expect(updateExpenseBody["occurredAt"] as? Int, equals: 1_710_000_030_000, prefix: "update-expense-request-occurred-at")
        expect(updateExpenseBody["long"] as? String, equals: nil, prefix: "update-expense-request-no-empty-long")
        expect(updateExpenseBody["lat"] as? String, equals: nil, prefix: "update-expense-request-no-empty-lat")

        let settlementBody = settlementRecordBody(groupCode: "AB12", recordId: "record_2", fromId: "user_2", toId: "user_1", amountMinor: "3000", note: "Transfer", occurredAt: 1_710_000_040_000)
        assertNoLegacyFields(settlementBody, prefix: "settlement-request")
        expect(settlementBody["type"] as? String, equals: "settlement", prefix: "settlement-request-type")
        expect(settlementBody["amount"] as? String, equals: "30.00", prefix: "settlement-request-amount")
        expect(settlementBody["fromId"] as? String, equals: "user_2", prefix: "settlement-request-from")
        expect(settlementBody["toId"] as? String, equals: "user_1", prefix: "settlement-request-to")
        expect(settlementBody["recordId"] as? String, equals: "record_2", prefix: "settlement-request-id")
        expect(settlementBody["createdAt"] as? Int, equals: nil, prefix: "settlement-request-no-client-created-at")
        expect(settlementBody["occurredAt"] as? Int, equals: 1_710_000_040_000, prefix: "settlement-request-occurred-at")

        let group = mapGroup([
            "code": "AB12",
            "name": "Japan Trip",
            "ownerUserId": "user_1",
            "archivedUserIds": ["user_1"],
            "isOwner": true,
            "createdAt": 1_710_000_000_000,
            "modifiedAt": 1_710_000_010_000,
            "currentUserBalance": "10.00",
            "currentUserExpenseShare": "33.34",
            "currentUserPaidTotal": "100.00",
            "currentUserRecordCount": 2,
            "participants": [
                [
                    "participantId": "user_1",
                    "kind": "user",
                    "userId": "user_1",
                    "profile": ["name": "Hong", "avatar": "avatar.png"],
                    "balance": "66.66",
                    "expenseShare": "33.34",
                    "recordCount": 1
                ],
                [
                    "participantId": "tmp_1",
                    "kind": "tempUser",
                    "tempName": "Guest",
                    "balance": "-33.33",
                    "expenseShare": "33.33",
                    "recordCount": 1
                ]
            ]
        ])
        expect(group.id, equals: "AB12", prefix: "group-code")
        expect(group.hasCurrentUserBalanceSummary, equals: true, prefix: "group-summary-flag")
        expect(group.currentUserBalanceMinor, equals: "1000", prefix: "group-current-balance")
        expect(group.membersInfo.first?.uuid, equals: "user_1", prefix: "formal-participant-id")
        expect(group.membersInfo.first?.name, equals: "Hong", prefix: "formal-profile-name")
        expect(group.membersInfo.first?.debtMinor, equals: "6666", prefix: "formal-balance")
        expect(group.tempUsers.first?.uuid, equals: "tmp_1", prefix: "temp-participant-id")
        expect(group.tempUsers.first?.name, equals: "Guest", prefix: "temp-name")
        expect(group.tempUsers.first?.debtMinor, equals: "-3333", prefix: "temp-balance")

        let groupSummary = mapGroup([
            "code": "CD34",
            "name": "Summary only",
            "ownerUserId": "user_1",
            "archivedUserIds": [],
            "isOwner": false,
            "createdAt": 1_710_000_000_000,
            "modifiedAt": 1_710_000_010_000,
            "currentUserBalance": "-4.56",
            "currentUserExpenseShare": "12.34",
            "currentUserPaidTotal": "7.89",
            "currentUserRecordCount": 4,
            "participantCount": 3,
            "participantPreview": [
                [
                    "participantId": "user_1",
                    "kind": "user",
                    "userId": "user_1",
                    "profile": ["name": "Hong", "avatar": "avatar.png"]
                ],
                [
                    "participantId": "tmp_1",
                    "kind": "tempUser",
                    "tempName": "Guest"
                ]
            ]
        ])
        expect(groupSummary.allMembers.count, equals: 0, prefix: "summary-no-full-members")
        expect(groupSummary.participantCount, equals: 3, prefix: "summary-participant-count")
        expect(groupSummary.participantPreview.count, equals: 2, prefix: "summary-preview-count")
        expect(groupSummary.participantPreview.first?.name, equals: "Hong", prefix: "summary-preview-formal-name")
        expect(groupSummary.participantPreview.last?.isTemporary, equals: Optional(true), prefix: "summary-preview-temp-flag")

        let balances = mapParticipants([
            [
                "participantId": "user_1",
                "kind": "user",
                "profile": ["name": "Hong"],
                "balance": "66.66",
                "expenseShare": "33.34",
                "recordCount": 2
            ],
            [
                "participantId": "tmp_1",
                "kind": "tempUser",
                "tempName": "Guest",
                "balance": "-33.33",
                "expenseShare": "33.33",
                "recordCount": 1
            ]
        ])
        expect(balances.count, equals: 2, prefix: "balances-count")
        expect(balances.first?.uuid, equals: "user_1", prefix: "balances-formal-id")
        expect(balances.first?.debtMinor, equals: "6666", prefix: "balances-formal-balance")
        expect(balances.first?.recordCount, equals: 2, prefix: "balances-formal-record-count")
        expect(balances.last?.isTemporary, equals: true, prefix: "balances-temp-kind")

        let memberRecordPage = mapMemberRecordPage([
            "participantId": "user_2",
            "kind": "user",
            "profile": ["name": "Ada"],
            "balance": "-30.00",
            "expenseShare": "30.00",
            "paidTotal": "0.00",
            "recordCount": 2,
            "records": [
                [
                    "recordId": "record_3",
                    "groupCode": "AB12",
                    "type": "settlement",
                    "amount": "30.00",
                    "fromId": "user_2",
                    "toId": "user_1",
                    "createdAt": 1_710_000_050_000
                ]
            ]
        ])
        expect(memberRecordPage.member?.uuid, equals: "user_2", prefix: "member-page-id")
        expect(memberRecordPage.member?.debtMinor, equals: "-3000", prefix: "member-page-balance")
        expect(memberRecordPage.member?.costMinor, equals: "3000", prefix: "member-page-expense-share")
        expect(memberRecordPage.member?.recordCount, equals: 2, prefix: "member-page-record-count")
        expect(memberRecordPage.records.count, equals: 1, prefix: "member-page-records")
        expect(memberRecordPage.records.first?.isDebtResolve, equals: true, prefix: "member-page-settlement-record")

        let expense = mapRecord([
            "recordId": "record_1",
            "groupCode": "AB12",
            "type": "expense",
            "amount": "100.00",
            "payerId": "user_1",
            "participantIds": ["user_1", "user_2", "tmp_1"],
            "category": "food",
            "note": "Dinner",
            "createdAt": 1_710_000_000_000,
            "occurredAt": 1_710_000_005_000,
            "updatedAt": 1_710_000_010_000,
            "createdBy": "user_1",
            "updatedBy": "user_1"
        ])
        expect(expense.recordId, equals: "record_1", prefix: "expense-id")
        expect(expense.who, equals: "user_1", prefix: "expense-payer")
        expect(expense.paidMinor, equals: "10000", prefix: "expense-amount")
        expect(expense.forWhom, equals: ["user_1", "user_2", "tmp_1"], prefix: "expense-participants")
        expect(expense.type, equals: "food", prefix: "expense-category")
        expect(expense.text, equals: "Dinner", prefix: "expense-note")
        expect(expense.createdAt, equals: 1_710_000_000_000, prefix: "expense-created-at")
        expect(expense.occurredAt, equals: 1_710_000_005_000, prefix: "expense-occurred-at")
        expect(expense.isDebtResolve, equals: false, prefix: "expense-not-settlement")

        let settlement = mapRecord([
            "recordId": "record_2",
            "groupCode": "AB12",
            "type": "settlement",
            "amount": "30.00",
            "fromId": "user_2",
            "toId": "user_1",
            "category": "settlement",
            "createdAt": 1_710_000_020_000,
            "occurredAt": 1_710_000_025_000
        ])
        expect(settlement.recordId, equals: "record_2", prefix: "settlement-id")
        expect(settlement.who, equals: "user_2", prefix: "settlement-from")
        expect(settlement.forWhom, equals: ["user_1"], prefix: "settlement-to")
        expect(settlement.paidMinor, equals: "3000", prefix: "settlement-amount")
        expect(settlement.type, equals: transferCategory.id, prefix: "settlement-category")
        expect(settlement.occurredAt, equals: 1_710_000_025_000, prefix: "settlement-occurred-at")
        expect(settlement.isDebtResolve, equals: true, prefix: "settlement-flag")
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }

    private static func assertNoLegacyFields(_ body: [String: Any], prefix: String) {
        let legacyFields = Set(["paid", "paidMinor", "debtMinor", "costMinor", "forWhom", "isDebtResolve"])
        let present = legacyFields.intersection(body.keys)
        assert(present.isEmpty, "\(prefix): legacy request fields present \(present.sorted())")
    }
}
#endif
