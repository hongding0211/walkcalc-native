#if DEBUG
import Foundation

@MainActor
enum LedgerRepositoryVerification {
    static func assertAllCasesPass() async {
        let oldFilters = try! JSONDecoder().decode(GroupRecordFilters.self, from: Data(#"{"currencyCodes":["USD"],"onlyRelatedToMe":true}"#.utf8))
        expect(oldFilters, equals: GroupRecordFilters(currencyCodes: ["USD"], onlyRelatedToMe: true), prefix: "filter-backward-compatible")
        let persisted = GroupRecordFilters(currencyCodes: ["USD"], onlyRelatedToMe: true, categoryIds: ["food", "traffic"])
        expect(try! JSONDecoder().decode(GroupRecordFilters.self, from: JSONEncoder().encode(persisted)), equals: persisted, prefix: "category-filter-persistence")
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

        let createGroup = await repository.createGroup(name: "Local Trip", currencyCode: "CNY", context: localContext)
        let groupId = expectSuccess(createGroup, prefix: "create-group").value ?? ""
        expect(groupId.isEmpty, equals: false, prefix: "created-group-id")

        let secondGroupID = expectSuccess(await repository.createGroup(name: "Second", currencyCode: "CNY", context: localContext), prefix: "pin-create-second").value!
        let thirdGroupID = expectSuccess(await repository.createGroup(name: "Third", currencyCode: "CNY", context: localContext), prefix: "pin-create-third").value!
        let firstPin = expectSuccess(await repository.pinGroup(code: secondGroupID, isPinned: true, context: localContext), prefix: "pin-first").value!
        _ = expectSuccess(await repository.pinGroup(code: groupId, isPinned: true, context: localContext), prefix: "pin-second")
        let repeatedPin = expectSuccess(await repository.pinGroup(code: secondGroupID, isPinned: true, context: localContext), prefix: "pin-idempotent").value!
        expect(repeatedPin.pinnedAt, equals: firstPin.pinnedAt, prefix: "pin-preserve-order")
        let firstPinPage = expectSuccess(await repository.groups(page: 1, pageSize: 1, search: nil, context: localContext), prefix: "pin-page-1")
        let secondPinPage = expectSuccess(await repository.groups(page: 2, pageSize: 1, search: nil, context: localContext), prefix: "pin-page-2")
        expect(firstPinPage.items.map(\.id), equals: [secondGroupID], prefix: "oldest-pin-first")
        expect(secondPinPage.items.map(\.id), equals: [groupId], prefix: "pin-before-pagination")
        _ = expectSuccess(await repository.pinGroup(code: secondGroupID, isPinned: false, context: localContext), prefix: "unpin")
        _ = expectSuccess(await repository.pinGroup(code: secondGroupID, isPinned: true, context: localContext), prefix: "repin")
        let allPins = expectSuccess(await repository.groups(page: 1, pageSize: 10, search: nil, context: localContext), prefix: "repin-page")
        expect(allPins.items.map(\.id), equals: [groupId, secondGroupID, thirdGroupID], prefix: "repin-goes-last")
        let remoteOrder = Array(allPins.items.reversed())
        expect(WalkGroup.mergingLocalGroups([], into: remoteOrder).map(\.id), equals: remoteOrder.map(\.id), prefix: "preserve-server-order")

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

        var categorySearch = RecordSearchRequest.noteOrCategoryName(query: "Dinner")
        categorySearch.currencyCodes = ["CNY"]
        categorySearch.participantId = guestId
        categorySearch.categoryIds = ["food", "traffic"]
        let categoryMatch = await repository.records(groupId: groupId, page: 1, pageSize: 10, search: categorySearch, context: localContext)
        expect(expectSuccess(categoryMatch, prefix: "local-category-combined").items.count, equals: 1, prefix: "local-category-combined-count")
        categorySearch.categoryIds = ["shopping"]
        let categoryMiss = await repository.records(groupId: groupId, page: 1, pageSize: 10, search: categorySearch, context: localContext)
        expect(expectSuccess(categoryMiss, prefix: "local-category-miss").items.count, equals: 0, prefix: "local-category-miss-count")
        var settlementFixture = record!
        settlementFixture.isDebtResolve = true
        settlementFixture.type = "transfer"
        categorySearch.categoryIds = ["traffic"]
        categorySearch.includeSettlements = true
        expect(categorySearch.matches(settlementFixture, defaultCurrency: "CNY"), equals: true, prefix: "local-settlement-included")
        categorySearch.currencyCodes = ["USD"]
        expect(categorySearch.matches(settlementFixture, defaultCurrency: "CNY"), equals: false, prefix: "local-settlement-retains-currency-filter")

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

        await verifyPersistentLocalPins(owner: owner)
        await verifyRemoteContracts()
        await verifyRemoteAuthFailures()
        NSLog("PASS: ledger repository and filtered request verification")
    }

    private static func verifyPersistentLocalPins(owner: Member) async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("walkcalc-pin-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.store")
        let context = LedgerSessionContext.local(owner: owner)
        var groupID = ""
        var pinnedAt: TimeInterval?
        do {
            let source = try! SwiftDataLedgerDataSource.temporaryPersistentStore(url: url)
            groupID = expectSuccess(await source.createGroup(name: "Saved pin", currencyCode: "CNY", context: context), prefix: "persistent-pin-group").value!
            pinnedAt = expectSuccess(await source.pinGroup(code: groupID, isPinned: true, context: context), prefix: "persistent-pin").value!.pinnedAt
        }
        let reloaded = try! SwiftDataLedgerDataSource.temporaryPersistentStore(url: url)
        let page = expectSuccess(await reloaded.groups(page: 1, pageSize: 1, search: nil, context: context), prefix: "persistent-pin-reload")
        expect(page.items.first?.pinnedAt, equals: pinnedAt, prefix: "pin-survives-reopen")
        _ = expectSuccess(await reloaded.pinGroup(code: groupID, isPinned: false, context: context), prefix: "persistent-unpin")
        let detail = expectSuccess(await reloaded.groupDetail(groupId: groupID, recordPageSize: 1, context: context), prefix: "persistent-unpin-detail")
        expect(detail.group?.isPinned, equals: Optional(false), prefix: "persistent-unpin-state")
    }

    private static let mockBaseURL = URL(string: "https://ledger-verification.invalid/api")!

    private static func verifyRemoteContracts() async {
        MockLedgerURLProtocol.reset()
        var api = APIClient()
        api.baseURL = mockBaseURL
        let repository = LedgerRepository(remoteSource: RemoteLedgerDataSource(api: api))
        let context = LedgerSessionContext.remote(accessToken: "valid-token")

        let pin = expectSuccess(await repository.pinGroup(code: "AB12", isPinned: true, context: context), prefix: "remote-pin").value!
        expect(pin.pinnedAt, equals: Optional(1_710_000_000_123), prefix: "remote-pin-timestamp")
        let unpin = expectSuccess(await repository.pinGroup(code: "AB12", isPinned: false, context: context), prefix: "remote-unpin").value!
        expect(unpin.pinnedAt, equals: nil, prefix: "remote-unpin-null")
        expect(MockLedgerURLProtocol.requests.filter { $0.path.hasSuffix("/pin") }.map(\.timeout), equals: [15, 15], prefix: "pin-request-timeout")
        let home = expectSuccess(await repository.home(page: 1, pageSize: 20, search: nil, context: context), prefix: "remote-home")
        expect(home.groups.first?.pinnedAt, equals: Optional(1_710_000_000_123), prefix: "remote-list-pin")
        expect(home.currencyBalances.count, equals: 2, prefix: "remote-home-currency-count")
        expect(home.currencyBalances.first { $0.currencyCode == "CNY" }?.totalBalanceMinor, equals: Optional("1000"), prefix: "remote-home-cny-balance")
        expect(home.currencyBalances.first { $0.currencyCode == "USD" }?.totalBalanceMinor, equals: Optional("-250"), prefix: "remote-home-usd-balance")
        _ = expectSuccess(await repository.groups(page: 2, pageSize: 20, search: "trip", context: context), prefix: "remote-groups")
        _ = expectSuccess(await repository.groupDetail(groupId: "AB12", recordPageSize: 10, context: context), prefix: "remote-group-detail")
        _ = expectSuccess(await repository.groupBalances(groupId: "AB12", context: context), prefix: "remote-balances")
        let usdSuggestion = expectSuccess(await repository.settlementSuggestion(groupId: "AB12", currencyCode: "USD", context: context), prefix: "remote-usd-settlement-suggestion").value ?? []
        expect(usdSuggestion.first?.currencyCode, equals: Optional("USD"), prefix: "remote-usd-settlement-currency")
        _ = expectSuccess(await repository.records(groupId: "AB12", page: 1, pageSize: 10, search: .noteOrCategoryName(query: "Dinner"), context: context), prefix: "remote-record-search")
        _ = expectSuccess(await repository.memberRecords(groupId: "AB12", memberId: "user-1", page: 1, pageSize: 10, context: context), prefix: "remote-member-records")
        _ = expectSuccess(await repository.createGroup(name: "New Group", currencyCode: "CNY", context: context), prefix: "remote-create-group")
        _ = expectSuccess(await repository.invite(code: "AB12", userIds: ["user-2"], context: context), prefix: "remote-invite")
        _ = expectSuccess(await repository.addTempUser(code: "AB12", name: "Guest", context: context), prefix: "remote-add-temp")
        _ = expectSuccess(await repository.changeGroupName(code: "AB12", name: "Renamed", context: context), prefix: "remote-rename")
        _ = expectSuccess(await repository.archiveGroup(code: "AB12", context: context), prefix: "remote-archive")
        _ = expectSuccess(await repository.unarchiveGroup(code: "AB12", context: context), prefix: "remote-unarchive")
        _ = expectSuccess(await repository.addRecord(groupId: "AB12", who: "user-1", paidMinor: "1200", forWhom: ["user-1", "tmp-1"], type: "food", text: "Dinner", long: "", lat: "", occurredAt: 1_710_000_000_000, currencyCode: "USD", context: context), prefix: "remote-add-record")
        _ = expectSuccess(await repository.updateRecord(groupId: "AB12", recordId: "record-1", who: "user-1", paidMinor: "1300", forWhom: ["user-1"], type: "food", text: "Updated", occurredAt: 1_710_000_000_001, isSettlement: false, currencyCode: "USD", context: context), prefix: "remote-update-record")
        _ = expectSuccess(await repository.deleteRecord(groupId: "AB12", recordId: "record-1", context: context), prefix: "remote-delete-record")
        _ = expectSuccess(await repository.addSettlementRecord(groupId: "AB12", fromId: "tmp-1", toId: "user-1", amountMinor: "600", note: "resolve", currencyCode: "USD", context: context), prefix: "remote-settlement-record")
        _ = expectSuccess(await repository.resolveDebts(groupId: "AB12", currencyCode: "USD", context: context), prefix: "remote-resolve-all")
        _ = expectSuccess(await repository.deleteGroup(code: "AB12", context: context), prefix: "remote-delete-group")

        let filters = RecordSearchRequest(operator: "or", conditions: [], currencyCodes: ["CNY", "USD"], participantId: "user-1")
        _ = expectSuccess(await repository.groupDetail(groupId: "AB12", recordPageSize: 10, recordSearch: filters, context: context), prefix: "remote-filter-first-page")
        _ = expectSuccess(await repository.records(groupId: "AB12", page: 2, pageSize: 10, search: filters, context: context), prefix: "remote-filter-next-page")
        let filteredRequests = MockLedgerURLProtocol.requests.filter { $0.path == "/api/walkcalc/groups/AB12/records" && $0.query["currencyCodes"] != nil }
        expect(filteredRequests.count, equals: 2, prefix: "remote-filter-count")
        expect(filteredRequests.allSatisfy { $0.query["currencyCodes"] == "CNY,USD" && $0.query["participantId"] == "user-1" && $0.query["search"] == nil }, equals: true, prefix: "remote-filter-query")

        var combinedSearch = RecordSearchRequest.noteOrCategoryName(query: "Dinner")
        combinedSearch.currencyCodes = filters.currencyCodes
        combinedSearch.participantId = filters.participantId
        combinedSearch.categoryIds = ["food", "transfer"]
        combinedSearch.includeSettlements = true
        _ = expectSuccess(await repository.groupDetail(groupId: "AB12", recordPageSize: 10, recordSearch: combinedSearch, context: context), prefix: "remote-combined-first-page")
        _ = expectSuccess(await repository.records(groupId: "AB12", page: 2, pageSize: 10, search: combinedSearch, context: context), prefix: "remote-combined-next-page")
        let combinedRequests = MockLedgerURLProtocol.requests.filter {
            $0.path == "/api/walkcalc/groups/AB12/records" && $0.query["currencyCodes"] != nil && $0.query["search"] != nil
        }
        expect(combinedRequests.count, equals: 2, prefix: "remote-combined-count")
        expect(Set(combinedRequests.compactMap { $0.query["page"] }), equals: Set(["1", "2"]), prefix: "remote-combined-pages")
        expect(combinedRequests.allSatisfy {
            $0.query["currencyCodes"] == "CNY,USD" && $0.query["participantId"] == "user-1"
                && $0.query["categoryIds"] == "food,transfer" && $0.query["includeSettlements"] == "true"
                && $0.query["search"]?.contains("Dinner") == true
                && $0.query["search"]?.contains("\"field\":\"note\"") == true
                && $0.query["search"]?.contains("\"field\":\"categoryName\"") == true
        }, equals: true, prefix: "remote-combined-query")

        let requests = MockLedgerURLProtocol.requests
        expect(requests.containsPath("/api/walkcalc/home/summary", method: "GET"), equals: true, prefix: "remote-home-summary-path")
        expect(requests.containsPath("/api/walkcalc/groups/my", method: "GET"), equals: true, prefix: "remote-groups-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12", method: "GET"), equals: true, prefix: "remote-group-detail-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/records", method: "GET"), equals: true, prefix: "remote-records-path")
        expect(requests.containsPath("/api/walkcalc/groups/AB12/balances", method: "GET"), equals: true, prefix: "remote-balances-path")
        expect(requests.first { $0.path == "/api/walkcalc/groups/AB12/settlement-suggestion" }?.query["currencyCode"], equals: Optional("USD"), prefix: "remote-settlement-suggestion-currency-query")
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
        let currencyRecordRequests = requests.filter { $0.path == "/api/walkcalc/records" || $0.path == "/api/walkcalc/records/update" }
        expect(currencyRecordRequests.allSatisfy { $0.body["currencyCode"] as? String == "USD" }, equals: true, prefix: "remote-record-currency-body")
        expect(requests.first { $0.path == "/api/walkcalc/groups/AB12/settlements/resolve" }?.body["currencyCode"] as? String, equals: Optional("USD"), prefix: "remote-resolve-currency-body")
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
    var timeout: TimeInterval
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
        Self.requests.append(MockLedgerRequest(method: method, path: path, query: query, body: body, timeout: request.timeoutInterval))

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
            return (200, envelope([
                "totalBalance": "7.50",
                "balances": [
                    ["currencyCode": "CNY", "totalBalance": "10.00"],
                    ["currencyCode": "USD", "totalBalance": "-2.50"]
                ]
            ]))
        case ("GET", "/api/walkcalc/groups/my"):
            return (200, pagedEnvelope([groupPayload(code: "AB12")], page: Int(query["page"] ?? "1") ?? 1, pageSize: Int(query["pageSize"] ?? "20") ?? 20, total: 2))
        case ("GET", "/api/walkcalc/groups/AB12"):
            return (200, envelope(groupPayload(code: "AB12")))
        case ("GET", "/api/walkcalc/groups/AB12/records"):
            return (200, pagedEnvelope([recordPayload(id: "record-1")], page: Int(query["page"] ?? "1") ?? 1, pageSize: Int(query["pageSize"] ?? "10") ?? 10, total: 1))
        case ("GET", "/api/walkcalc/groups/AB12/balances"):
            return (200, envelope(["participants": participantsPayload()]))
        case ("GET", "/api/walkcalc/groups/AB12/settlement-suggestion"):
            return (200, envelope([
                "groupCode": "AB12",
                "currencyCode": query["currencyCode"] ?? "CNY",
                "strategy": "exact",
                "transfers": [["fromId": "tmp-1", "toId": "user-1", "amount": "10.00"]]
            ]))
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
        case ("PATCH", "/api/walkcalc/groups/AB12/pin"):
            guard let pinned = body["isPinned"] as? Bool else { return (400, ["success": false]) }
            return (200, envelope(["code": "AB12", "pinnedAt": pinned ? (1_710_000_000_123 as Any) : NSNull()]))
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
            "pinnedAt": 1_710_000_000_123,
            "name": "Remote Trip",
            "ownerUserId": "user-1",
            "isOwner": true,
            "createdAt": 1_710_000_000_000,
            "modifiedAt": 1_710_000_000_000,
            "currentUserBalance": "10.00",
            "currentUserCurrencyBalances": [[
                "currencyCode": "USD",
                "balance": "10.00",
                "expenseShare": "6.00",
                "paidTotal": "12.00",
                "recordCount": 1,
                "settlementIn": "0.00",
                "settlementOut": "0.00"
            ]],
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
                "recordCount": 1,
                "currencyBalances": [[
                    "currencyCode": "USD",
                    "balance": "10.00",
                    "expenseShare": "6.00",
                    "paidTotal": "12.00",
                    "recordCount": 1,
                    "settlementIn": "0.00",
                    "settlementOut": "0.00"
                ]]
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
            "currencyCode": "USD",
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
