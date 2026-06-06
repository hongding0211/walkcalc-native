#if DEBUG
import Foundation

@MainActor
enum LedgerRepositoryVerification {
    static func assertAllCasesPass() async {
        URLProtocol.registerClass(MockLedgerURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLedgerURLProtocol.self)
            NativeAuthSession.clearAuthCookies(baseURL: mockBaseURL, webBaseURL: mockBaseURL)
        }

        let owner = Member(uuid: "local-owner", name: "Me", avatar: "", debtMinor: "0", costMinor: "0")
        let localSource = InMemoryLedgerDataSource()
        let repository = LedgerRepository(
            remoteSource: InMemoryLedgerDataSource(),
            localSource: localSource
        )
        let localContext = LedgerSessionContext.local(owner: owner)
        let remoteContext = LedgerSessionContext.remote(accessToken: nil)

        let createGroup = await repository.createGroup(name: "Local Trip", context: localContext)
        let groupId = expectSuccess(createGroup, prefix: "create-group").value ?? ""
        expect(groupId.isEmpty, equals: false, prefix: "created-group-id")

        let addTemp = await repository.addTempUser(code: groupId, name: "Guest", context: localContext)
        let guestId = expectSuccess(addTemp, prefix: "add-temp-user").value ?? ""
        expect(guestId.hasPrefix("lm-"), equals: true, prefix: "temp-id-prefix")

        let groupDetail = await repository.groupDetail(groupId: groupId, recordPageSize: 10, context: localContext)
        let group = expectSuccess(groupDetail, prefix: "group-detail").group
        expect(group?.allMembers.count, equals: Optional(2), prefix: "group-member-count")

        let addRecord = await repository.addRecord(
            groupId: groupId,
            who: owner.uuid,
            paidMinor: "1200",
            forWhom: [owner.uuid, guestId],
            type: "food",
            text: "Dinner",
            long: "",
            lat: "",
            occurredAt: 1_710_000_000_000,
            context: localContext
        )
        let record = expectSuccess(addRecord, prefix: "add-record").value
        expect(record?.text, equals: Optional("Dinner"), prefix: "record-note")

        let search = await repository.records(
            groupId: groupId,
            page: 1,
            pageSize: 10,
            search: .noteOrCategoryName(query: "Dinner"),
            context: localContext
        )
        expect(expectSuccess(search, prefix: "record-search").items.count, equals: 1, prefix: "record-search-count")

        let memberRecords = await repository.memberRecords(groupId: groupId, memberId: guestId, page: 1, pageSize: 10, context: localContext)
        expect(expectSuccess(memberRecords, prefix: "member-records").records.count, equals: 1, prefix: "member-record-count")

        let settlement = await repository.settlementSuggestion(groupId: groupId, context: localContext)
        let transfers = expectSuccess(settlement, prefix: "settlement-suggestion").value ?? []
        expect(transfers.count, equals: 1, prefix: "settlement-count")
        expect(transfers.first?.fromId, equals: Optional(guestId), prefix: "settlement-from")
        expect(transfers.first?.toId, equals: Optional(owner.uuid), prefix: "settlement-to")

        let deleteRecord = await repository.deleteRecord(groupId: groupId, recordId: record?.recordId ?? "", context: localContext)
        _ = expectSuccess(deleteRecord, prefix: "delete-record")

        let remoteOnly = await repository.joinGroup(code: "ABCD", context: remoteContext)
        expectFailure(remoteOnly, kind: .authenticationRequired, prefix: "join-auth-required")

        let unavailable = await repository.home(
            page: 1,
            pageSize: 10,
            search: nil,
            context: LedgerSessionContext(accessToken: nil, localOwner: owner, localSourceAvailable: false, preferredSource: .local)
        )
        expectFailure(unavailable, kind: .sourceUnavailable, prefix: "source-unavailable")

        await verifyRemoteContracts()
        await verifyRemoteAuthFailures()
    }

    private static let mockBaseURL = URL(string: "https://ledger-verification.invalid/api")!

    private static func verifyRemoteContracts() async {
        MockLedgerURLProtocol.reset()
        var api = APIClient()
        api.baseURL = mockBaseURL
        let repository = LedgerRepository(remoteSource: RemoteLedgerDataSource(api: api))
        let context = LedgerSessionContext.remote(accessToken: "valid-token")

        _ = expectSuccess(await repository.home(page: 1, pageSize: 20, search: nil, context: context), prefix: "remote-home")
        _ = expectSuccess(await repository.groups(page: 2, pageSize: 20, search: "trip", context: context), prefix: "remote-groups")
        _ = expectSuccess(await repository.groupDetail(groupId: "AB12", recordPageSize: 10, context: context), prefix: "remote-group-detail")
        _ = expectSuccess(await repository.groupBalances(groupId: "AB12", context: context), prefix: "remote-balances")
        _ = expectSuccess(await repository.records(groupId: "AB12", page: 1, pageSize: 10, search: .noteOrCategoryName(query: "Dinner"), context: context), prefix: "remote-record-search")
        _ = expectSuccess(await repository.memberRecords(groupId: "AB12", memberId: "user-1", page: 1, pageSize: 10, context: context), prefix: "remote-member-records")
        _ = expectSuccess(await repository.createGroup(name: "New Group", context: context), prefix: "remote-create-group")
        _ = expectSuccess(await repository.invite(code: "AB12", userIds: ["user-2"], context: context), prefix: "remote-invite")
        _ = expectSuccess(await repository.addTempUser(code: "AB12", name: "Guest", context: context), prefix: "remote-add-temp")
        _ = expectSuccess(await repository.changeGroupName(code: "AB12", name: "Renamed", context: context), prefix: "remote-rename")
        _ = expectSuccess(await repository.archiveGroup(code: "AB12", context: context), prefix: "remote-archive")
        _ = expectSuccess(await repository.unarchiveGroup(code: "AB12", context: context), prefix: "remote-unarchive")
        _ = expectSuccess(await repository.addRecord(groupId: "AB12", who: "user-1", paidMinor: "1200", forWhom: ["user-1", "tmp-1"], type: "food", text: "Dinner", long: "", lat: "", occurredAt: 1_710_000_000_000, context: context), prefix: "remote-add-record")
        _ = expectSuccess(await repository.updateRecord(groupId: "AB12", recordId: "record-1", who: "user-1", paidMinor: "1300", forWhom: ["user-1"], type: "food", text: "Updated", occurredAt: 1_710_000_000_001, isSettlement: false, context: context), prefix: "remote-update-record")
        _ = expectSuccess(await repository.deleteRecord(groupId: "AB12", recordId: "record-1", context: context), prefix: "remote-delete-record")
        _ = expectSuccess(await repository.addSettlementRecord(groupId: "AB12", fromId: "tmp-1", toId: "user-1", amountMinor: "600", note: "resolve", context: context), prefix: "remote-settlement-record")
        _ = expectSuccess(await repository.resolveDebts(groupId: "AB12", context: context), prefix: "remote-resolve-all")
        _ = expectSuccess(await repository.deleteGroup(code: "AB12", context: context), prefix: "remote-delete-group")

        let requests = MockLedgerURLProtocol.requests
        expect(requests.containsPath("/api/walkcalc/home/summary", method: "GET"), equals: true, prefix: "remote-home-summary-path")
        expect(requests.containsPath("/api/walkcalc/groups/my", method: "GET"), equals: true, prefix: "remote-groups-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12", method: "GET"), equals: true, prefix: "remote-group-detail-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/records", method: "GET"), equals: true, prefix: "remote-records-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/balances", method: "GET"), equals: true, prefix: "remote-balances-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/balances/user-1/records", method: "GET"), equals: true, prefix: "remote-member-records-path")
        expect(requests.containsPath("/api/walkcalc/groups", method: "POST"), equals: true, prefix: "remote-create-group-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/invite", method: "POST"), equals: true, prefix: "remote-invite-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/temp-users", method: "POST"), equals: true, prefix: "remote-temp-user-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/name", method: "PATCH"), equals: true, prefix: "remote-rename-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/archive", method: "POST"), equals: true, prefix: "remote-archive-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/unarchive", method: "POST"), equals: true, prefix: "remote-unarchive-path")
        expect(requests.containsPath("/api/walkcalc/records", method: "POST"), equals: true, prefix: "remote-add-record-path")
        expect(requests.containsPath("/api/walkcalc/records/update", method: "POST"), equals: true, prefix: "remote-update-record-path")
        expect(requests.containsPath("/api/walkcalc/records/drop", method: "POST"), equals: true, prefix: "remote-delete-record-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/settlements/resolve", method: "POST"), equals: true, prefix: "remote-resolve-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12", method: "DELETE"), equals: true, prefix: "remote-delete-group-path")

        let searchRequest = requests.first { $0.path == "/api/walkcalc/groups/AB12/records" && $0.query["search"]?.contains("Dinner") == true }
        expect(searchRequest?.query["search"]?.contains("\"operator\":\"or\""), equals: Optional(true), prefix: "remote-search-operator")
        expect(searchRequest?.query["search"]?.contains("\"field\":\"note\""), equals: Optional(true), prefix: "remote-search-note")
        expect(searchRequest?.query["search"]?.contains("\"field\":\"categoryName\""), equals: Optional(true), prefix: "remote-search-category")
    }

    private static func verifyRemoteAuthFailures() async {
        var api = APIClient()
        api.baseURL = mockBaseURL
        let repository = LedgerRepository(remoteSource: RemoteLedgerDataSource(api: api))

        let missingToken = await repository.joinGroup(code: "AB12", context: .remote(accessToken: nil))
        expectFailure(missingToken, kind: .authenticationRequired, prefix: "remote-missing-token")

        MockLedgerURLProtocol.reset(mode: .refreshableAuthFailure)
        NativeAuthSession.storeRefreshToken("valid-refresh", for: mockBaseURL)
        let refreshed = await repository.groups(page: 1, pageSize: 20, search: nil, context: .remote(accessToken: "expired-token"))
        let refreshedPage = expectSuccess(refreshed, prefix: "remote-refresh-success")
        expect(refreshedPage.refreshedToken, equals: Optional("refreshed-token"), prefix: "remote-refreshed-token")

        MockLedgerURLProtocol.reset(mode: .unrecoverableAuthFailure)
        NativeAuthSession.clearAuthCookies(baseURL: mockBaseURL, webBaseURL: mockBaseURL)
        let unrecoverable = await repository.groups(page: 1, pageSize: 20, search: nil, context: .remote(accessToken: "expired-token"))
        expectFailure(unrecoverable, kind: .unrecoverableAuth, prefix: "remote-unrecoverable-auth")

        MockLedgerURLProtocol.reset(mode: .serverEnvelopeFailure)
        let serverFailure = await repository.groups(page: 1, pageSize: 20, search: nil, context: .remote(accessToken: "valid-token"))
        expectFailure(serverFailure, kind: .recoverableNetwork, prefix: "remote-server-envelope-failure")
    }

    private static func expectSuccess<Value>(_ result: LedgerOperationResult<Value>, prefix: String) -> Value {
        guard case .success(let value) = result else {
            assertionFailure("\(prefix): expected success")
            fatalError("\(prefix): expected success")
        }
        return value
    }

    private static func expectFailure<Value>(_ result: LedgerOperationResult<Value>, kind: LedgerOperationFailureKind, prefix: String) {
        guard case .failure(let failure) = result else {
            assertionFailure("\(prefix): expected failure")
            return
        }
        expect(failure.kind, equals: kind, prefix: prefix)
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }
}

private struct MockLedgerRequest {
    var method: String
    var path: String
    var query: [String: String]
    var body: [String: Any]
}

private extension Array where Element == MockLedgerRequest {
    func containsPath(_ path: String, method: String) -> Bool {
        contains { $0.path == path && $0.method == method }
    }
}

private final class MockLedgerURLProtocol: URLProtocol {
    enum Mode {
        case normal
        case refreshableAuthFailure
        case unrecoverableAuthFailure
        case serverEnvelopeFailure
    }

    static var mode: Mode = .normal
    static var requests: [MockLedgerRequest] = []
    private static var didReturnRefreshableAuthFailure = false

    static func reset(mode: Mode = .normal) {
        self.mode = mode
        requests = []
        didReturnRefreshableAuthFailure = false
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "ledger-verification.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let path = components?.path ?? ""
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        let body = jsonBody(from: request)
        Self.requests.append(MockLedgerRequest(method: method, path: path, query: query, body: body))

        let status: Int
        let payload: Any
        if Self.mode == .refreshableAuthFailure,
           path != "/api/auth/refreshToken",
           !Self.didReturnRefreshableAuthFailure {
            Self.didReturnRefreshableAuthFailure = true
            status = 401
            payload = ["success": false, "message": "expired"]
        } else if Self.mode == .unrecoverableAuthFailure {
            status = 401
            payload = ["success": false, "message": "expired"]
        } else if Self.mode == .serverEnvelopeFailure {
            status = 200
            payload = ["success": false, "message": "server envelope"]
        } else {
            (status, payload) = response(method: method, path: path, query: query, body: body)
        }

        let data = try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func jsonBody(from request: URLRequest) -> [String: Any] {
        guard let stream = request.httpBodyStream else {
            guard let data = request.httpBody,
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return body
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func response(method: String, path: String, query: [String: String], body: [String: Any]) -> (Int, Any) {
        switch (method, path) {
        case ("POST", "/api/auth/refreshToken"):
            return (200, envelope(["accessToken": "refreshed-token", "refreshToken": "next-refresh"]))
        case ("GET", "/api/walkcalc/home/summary"):
            return (200, envelope("10.00"))
        case ("GET", "/api/walkcalc/groups/my"):
            return (200, pagedEnvelope([groupPayload(code: "AB12")], page: Int(query["page"] ?? "1") ?? 1, pageSize: Int(query["pageSize"] ?? "20") ?? 20, total: 2))
        case ("GET", "/api/walkcalc/groups/AB12"):
            return (200, envelope(groupPayload(code: "AB12")))
        case ("GET", "/api/walkcalc/groups/AB12/records"):
            return (200, pagedEnvelope([recordPayload(id: "record-1")], page: Int(query["page"] ?? "1") ?? 1, pageSize: Int(query["pageSize"] ?? "10") ?? 10, total: 1))
        case ("GET", "/api/walkcalc/groups/AB12/balances"):
            return (200, envelope(["participants": participantsPayload()]))
        case ("GET", "/api/walkcalc/groups/AB12/balances/user-1/records"):
            var member = participantsPayload()[0]
            member["records"] = [recordPayload(id: "record-1")]
            return (200, pagedEnvelope(member, page: Int(query["page"] ?? "1") ?? 1, pageSize: Int(query["pageSize"] ?? "10") ?? 10, total: 1))
        case ("POST", "/api/walkcalc/groups"):
            return (200, envelope(["code": "AB12"]))
        case ("POST", "/api/walkcalc/groups/AB12/invite"):
            return (200, envelope(["userIds": body["userIds"] as? [String] ?? []]))
        case ("POST", "/api/walkcalc/groups/AB12/temp-users"):
            return (200, envelope(["participantId": "tmp-1"]))
        case ("PATCH", "/api/walkcalc/groups/AB12/name"):
            return (200, envelope(["name": body["name"] as? String ?? ""]))
        case ("POST", "/api/walkcalc/groups/AB12/archive"),
             ("POST", "/api/walkcalc/groups/AB12/unarchive"),
             ("DELETE", "/api/walkcalc/groups/AB12"):
            return (200, envelope(["code": "AB12"]))
        case ("POST", "/api/walkcalc/records"),
             ("POST", "/api/walkcalc/records/update"):
            return (200, envelope(["record": recordPayload(id: body["recordId"] as? String ?? "record-1")]))
        case ("POST", "/api/walkcalc/records/drop"):
            return (200, envelope(["recordId": body["recordId"] as? String ?? "record-1"]))
        case ("POST", "/api/walkcalc/groups/AB12/settlements/resolve"):
            return (200, envelope(["records": [recordPayload(id: "settlement-1", type: "settlement")]]))
        default:
            return (404, ["success": false, "message": "unhandled \(method) \(path)"])
        }
    }

    private func envelope(_ data: Any) -> [String: Any] {
        ["success": true, "data": data]
    }

    private func pagedEnvelope(_ data: Any, page: Int, pageSize: Int, total: Int) -> [String: Any] {
        ["success": true, "data": ["data": data, "page": page, "pageSize": pageSize, "total": total]]
    }

    private func groupPayload(code: String) -> [String: Any] {
        [
            "code": code,
            "name": "Remote Trip",
            "ownerUserId": "user-1",
            "isOwner": true,
            "createdAt": 1_710_000_000_000,
            "modifiedAt": 1_710_000_000_000,
            "currentUserBalance": "10.00",
            "participants": participantsPayload()
        ]
    }

    private func participantsPayload() -> [[String: Any]] {
        [
            [
                "participantId": "user-1",
                "kind": "user",
                "profile": ["name": "Me", "avatar": ""],
                "balance": "10.00",
                "expenseShare": "6.00",
                "recordCount": 1
            ],
            [
                "participantId": "tmp-1",
                "kind": "tempUser",
                "tempName": "Guest",
                "balance": "-10.00",
                "expenseShare": "6.00",
                "recordCount": 1
            ]
        ]
    }

    private func recordPayload(id: String, type: String = "expense") -> [String: Any] {
        [
            "recordId": id,
            "type": type,
            "amount": "12.00",
            "payerId": "user-1",
            "participantIds": ["user-1", "tmp-1"],
            "category": "food",
            "note": "Dinner",
            "createdAt": 1_710_000_000_000,
            "occurredAt": 1_710_000_000_000,
            "updatedAt": 1_710_000_000_000
        ]
    }
}
#endif
