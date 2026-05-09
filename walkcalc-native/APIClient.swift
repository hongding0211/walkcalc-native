import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case patch = "PATCH"
}

struct APIClient {
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
        components.queryItems = [URLQueryItem(name: "redirect", value: redirect)]
        return components.url!
    }

    func profileURL() -> URL {
        webBaseURL.appendingPathComponent("sso/profile")
    }

    func redirectPrefix() -> String {
        webBaseURL.appendingPathComponent("auth/callback").absoluteString
    }

    func userInfo(token: String) async throws -> APIEnvelope<UserProfile> {
        try await request(.get, path: "/walkcalc/users/me", token: token, mapper: mapUser)
    }

    func postUserMeta(token: String, metadata: [String: Any]) async throws -> APIEnvelope<[String: Any]> {
        try await request(.patch, path: "/auth/profile", token: token, body: ["metadata": metadata]) { raw in
            dictPayload(raw)
        }
    }

    func groups(token: String) async throws -> APIEnvelope<[WalkGroup]> {
        try await request(.get, path: "/walkcalc/groups/my", query: ["pageSize": "100"], token: token) { raw in
            arrayPayload(raw).map(mapGroup)
        }
    }

    func group(code: String, token: String) async throws -> APIEnvelope<WalkGroup> {
        try await request(.get, path: "/walkcalc/groups/\(code)", token: token, mapper: mapGroup)
    }

    func createGroup(name: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/groups", token: token, body: ["name": name]) { raw in
            dictPayload(raw)["code"] as? String ?? dictPayload(raw)["groupId"] as? String ?? ""
        }
    }

    func joinGroup(code: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/groups/join", token: token, body: ["code": code]) { raw in
            dictPayload(raw)["code"] as? String ?? dictPayload(raw)["groupId"] as? String ?? ""
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
            dictPayload(raw)["uuid"] as? String ?? name
        }
    }

    func searchUsers(name: String, token: String) async throws -> APIEnvelope<[UserProfile]> {
        try await request(.get, path: "/walkcalc/users/search", query: ["name": name], token: token) { raw in
            arrayPayload(raw).map(mapUser)
        }
    }

    func records(groupCode: String, page: Int, token: String) async throws -> APIEnvelope<[WalkRecord]> {
        try await request(.get, path: "/walkcalc/records/group/\(groupCode)", query: ["page": "\(page)"], token: token) { raw in
            arrayPayload(raw).map(mapRecord)
        }
    }

    func record(id: String, token: String) async throws -> APIEnvelope<WalkRecord> {
        try await request(.get, path: "/walkcalc/records/\(id)", token: token) { raw in
            if let first = arrayPayload(raw).first {
                return mapRecord(first)
            }
            return mapRecord(dictPayload(raw))
        }
    }

    func addRecord(groupCode: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, token: String, long: String = "", lat: String = "", isDebtResolve: Bool = false) async throws -> APIEnvelope<WalkRecord> {
        let body: [String: Any] = [
            "groupCode": groupCode,
            "who": who,
            "paidMinor": paidMinor,
            "forWhom": forWhom,
            "type": type,
            "text": text,
            "long": long,
            "lat": lat,
            "isDebtResolve": isDebtResolve
        ]
        return try await request(.post, path: "/walkcalc/records", token: token, body: body, mapper: mapRecord)
    }

    func updateRecord(groupCode: String, recordId: String, who: String, paidMinor: MoneyMinor, forWhom: [String], type: String, text: String, token: String) async throws -> APIEnvelope<WalkRecord> {
        let body: [String: Any] = [
            "groupCode": groupCode,
            "recordId": recordId,
            "who": who,
            "paidMinor": paidMinor,
            "forWhom": forWhom,
            "type": type,
            "text": text
        ]
        return try await request(.post, path: "/walkcalc/records/update", token: token, body: body, mapper: mapRecord)
    }

    func dropRecord(groupCode: String, recordId: String, token: String) async throws -> APIEnvelope<String> {
        try await request(.post, path: "/walkcalc/records/drop", token: token, body: ["groupCode": groupCode, "recordId": recordId]) { raw in
            dictPayload(raw)["recordId"] as? String ?? recordId
        }
    }

    func resolveDebts(groupCode: String, transfers: [[String: String]], token: String) async throws -> APIEnvelope<[WalkRecord]> {
        try await request(.post, path: "/walkcalc/records/resolve-debts", token: token, body: ["groupCode": groupCode, "transfers": transfers]) { raw in
            arrayPayload(raw).map(mapRecord)
        }
    }

    private func request<T>(_ method: HTTPMethod, path: String, query: [String: String] = [:], token: String, body: [String: Any]? = nil, mapper: (Any?) -> T) async throws -> APIEnvelope<T> {
        var response = try await execute(method, path: path, query: query, token: token, body: body)
        var refreshedToken: String?
        if response.status == 401 || response.status == 403 {
            if let nextToken = try? await refreshAccessToken() {
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

private func mapUser(_ raw: Any?) -> UserProfile {
    let dict = dictPayload(raw)
    let profile = dict["profile"] as? [String: Any] ?? [:]
    let uuid = dict["userId"] as? String ?? dict["uuid"] as? String ?? ""
    return UserProfile(
        uuid: uuid,
        name: profile["name"] as? String ?? dict["name"] as? String ?? uuid,
        avatar: profile["avatar"] as? String ?? dict["avatar"] as? String ?? ""
    )
}

private func mapMember(_ raw: [String: Any], temporary: Bool = false) -> Member {
    let profile = raw["profile"] as? [String: Any] ?? [:]
    let uuid = raw["userId"] as? String ?? raw["uuid"] as? String ?? ""
    let debtMinor = Money.normalize(raw["debtMinor"] ?? raw["debt"])
    let costMinor = Money.normalize(raw["costMinor"] ?? raw["cost"])
    return Member(
        uuid: uuid,
        name: profile["name"] as? String ?? raw["name"] as? String ?? uuid,
        avatar: profile["avatar"] as? String ?? raw["avatar"] as? String ?? "",
        debtMinor: debtMinor,
        costMinor: costMinor,
        isTemporary: temporary
    )
}

private func mapGroup(_ raw: Any?) -> WalkGroup {
    let dict = dictPayload(raw)
    let members = (dict["members"] as? [[String: Any]] ?? dict["membersInfo"] as? [[String: Any]] ?? []).map { mapMember($0) }
    let tempUsers = (dict["tempUsers"] as? [[String: Any]] ?? []).map { mapMember($0, temporary: true) }
    return WalkGroup(
        id: dict["code"] as? String ?? dict["id"] as? String ?? "",
        name: dict["name"] as? String ?? "",
        createdAt: timeInterval(dict["createdAt"]),
        modifiedAt: timeInterval(dict["modifiedAt"]),
        membersInfo: members,
        tempUsers: tempUsers,
        archivedUsers: dict["archivedUserIds"] as? [String] ?? dict["archivedUsers"] as? [String] ?? [],
        isOwner: dict["isOwner"] as? Bool ?? false
    )
}

private func mapRecord(_ raw: Any?) -> WalkRecord {
    let dict = dictPayload(raw)
    return WalkRecord(
        recordId: dict["recordId"] as? String ?? "",
        who: dict["who"] as? String ?? "",
        paidMinor: Money.normalize(dict["paidMinor"] ?? dict["paid"]),
        forWhom: dict["forWhom"] as? [String] ?? [],
        type: dict["type"] as? String ?? "food",
        text: dict["text"] as? String ?? "",
        long: dict["long"] as? String ?? "",
        lat: dict["lat"] as? String ?? "",
        createdAt: timeInterval(dict["createdAt"]),
        modifiedAt: timeInterval(dict["modifiedAt"]),
        isDebtResolve: dict["isDebtResolve"] as? Bool ?? false,
        createdBy: dict["createdBy"] as? String,
        modifiedBy: dict["modifiedBy"] as? String
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
