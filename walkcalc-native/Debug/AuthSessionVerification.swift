#if DEBUG
import Foundation

enum AuthSessionVerification {
    static func assertAllCasesPass() async {
        await verifyCookieImportAndClear()
        await verifyAppleNativeLoginStoresSession()
        await verifyRefreshRetryPersistsAccessToken()
        await verifyForegroundActivationRefreshesSession()
        await verifyMissingRefreshCredentialFailsAsAuthRefresh()
        await verifyTransportFailureRemainsNonAuth()
    }

    private static func verifyCookieImportAndClear() async {
        let baseURL = URL(string: "http://127.0.0.1:3500")!
        let webBaseURL = URL(string: "http://localhost:3000")!
        NativeAuthSession.clearAuthCookies(baseURL: baseURL, webBaseURL: webBaseURL)

        let result = NativeAuthSession.importAuthCookies([
            makeCookie(name: NativeAuthSession.accessCookieName, value: "access", domain: "localhost"),
            makeCookie(name: NativeAuthSession.refreshCookieName, value: "refresh", domain: "localhost"),
            makeCookie(name: "unrelated", value: "ignored", domain: "localhost")
        ].compactMap { $0 }, baseURL: baseURL, webBaseURL: webBaseURL)

        expect(result.hasRefreshCredential, equals: true, prefix: "auth-session-import-refresh")
        expect(NativeAuthSession.hasRefreshCredential(for: baseURL), equals: true, prefix: "auth-session-has-refresh")
        expect(UserDefaults.standard.string(forKey: NativeAuthSession.refreshCookieName), equals: nil, prefix: "auth-session-no-refresh-userdefaults")

        let store = WalkcalcStore()
        store.logout()
        expect(NativeAuthSession.hasRefreshCredential(for: baseURL), equals: false, prefix: "auth-session-clear-refresh")
    }

    private static func verifyAppleNativeLoginStoresSession() async {
        await withMockProtocol { calls in
            NativeAuthSession.clearAuthCookies(baseURL: APIClient().baseURL, webBaseURL: APIClient().webBaseURL)
            var capturedBody: [String: Any] = [:]
            MockURLProtocol.requestHandler = { request in
                let path = request.url?.path ?? ""
                calls.append((path, request.value(forHTTPHeaderField: "Authorization")))
                if path == "/auth/apple/native" {
                    capturedBody = jsonBody(from: request)
                    return httpResponse(status: 200, url: request.url!, json: [
                        "isSuccess": true,
                        "data": [
                            "accessToken": "apple-access-token",
                            "refreshToken": "apple-refresh-token",
                            "user": [
                                "userId": "apple-user",
                                "profile": [
                                    "name": "Apple User",
                                    "avatar": "avatar-url"
                                ]
                            ]
                        ]
                    ])
                }
                return httpResponse(status: 500, url: request.url!)
            }

            do {
                let response = try await APIClient().signInWithApple(
                    identityToken: "apple-identity-token",
                    authorizationCode: "apple-auth-code",
                    fullName: "Apple User",
                    nonce: "raw-nonce"
                )
                expect(response.success, equals: true, prefix: "auth-session-apple-success")
                expect(response.data?.accessToken, equals: Optional("apple-access-token"), prefix: "auth-session-apple-access-token")
                expect(response.data?.refreshToken, equals: Optional("apple-refresh-token"), prefix: "auth-session-apple-refresh-token")
                expect(response.data?.user?.uuid, equals: Optional("apple-user"), prefix: "auth-session-apple-user")
                expect(NativeAuthSession.refreshToken(for: APIClient().baseURL), equals: Optional("apple-refresh-token"), prefix: "auth-session-apple-refresh-persisted")
                expect(capturedBody["identityToken"] as? String, equals: Optional("apple-identity-token"), prefix: "auth-session-apple-body-identity")
                expect(capturedBody["authorizationCode"] as? String, equals: Optional("apple-auth-code"), prefix: "auth-session-apple-body-code")
                expect(capturedBody["fullName"] as? String, equals: Optional("Apple User"), prefix: "auth-session-apple-body-name")
                expect(capturedBody["nonce"] as? String, equals: Optional("raw-nonce"), prefix: "auth-session-apple-body-nonce")
            } catch {
                assertionFailure("auth-session-apple-native-login: unexpected error \(error)")
            }
            expect(calls.paths, equals: ["/auth/apple/native"], prefix: "auth-session-apple-call-order")
        }
    }

    private static func verifyRefreshRetryPersistsAccessToken() async {
        await withMockProtocol { calls in
            _ = NativeAuthSession.importAuthCookies([
                makeCookie(name: NativeAuthSession.refreshCookieName, value: "refresh", domain: "127.0.0.1")
            ].compactMap { $0 }, baseURL: APIClient().baseURL, webBaseURL: APIClient().webBaseURL)

            MockURLProtocol.requestHandler = { request in
                let path = request.url?.path ?? ""
                calls.append((path, request.value(forHTTPHeaderField: "Authorization")))
                if path == "/auth/info", request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-token" {
                    return httpResponse(status: 401, url: request.url!)
                }
                if path == "/auth/refreshToken" {
                    return httpResponse(
                        status: 200,
                        url: request.url!,
                        json: ["success": true, "data": ["accessToken": "fresh-token"]],
                        headers: ["Set-Cookie": "refreshToken=rotated; Path=/; HttpOnly"]
                    )
                }
                if path == "/auth/info", request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token" {
                    return httpResponse(status: 200, url: request.url!, json: [
                        "success": true,
                        "data": [
                            "userId": "user-1",
                            "profile": ["name": "Hong"]
                        ]
                    ])
                }
                return httpResponse(status: 500, url: request.url!)
            }

            let response = try? await APIClient().userInfo(token: "expired-token")
            expect(response?.success, equals: true, prefix: "auth-session-refresh-response")
            expect(response?.refreshedToken, equals: "fresh-token", prefix: "auth-session-refresh-token")
            expect(calls.paths, equals: ["/auth/info", "/auth/refreshToken", "/auth/info"], prefix: "auth-session-refresh-call-order")
        }
    }

    private static func verifyForegroundActivationRefreshesSession() async {
        await withMockProtocol { calls in
            _ = NativeAuthSession.importAuthCookies([
                makeCookie(name: NativeAuthSession.refreshCookieName, value: "refresh", domain: "127.0.0.1")
            ].compactMap { $0 }, baseURL: APIClient().baseURL, webBaseURL: APIClient().webBaseURL)

            MockURLProtocol.requestHandler = { request in
                let path = request.url?.path ?? ""
                calls.append((path, request.value(forHTTPHeaderField: "Authorization")))
                if path == "/auth/info", request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-token" {
                    return httpResponse(status: 401, url: request.url!)
                }
                if path == "/auth/refreshToken" {
                    return httpResponse(
                        status: 200,
                        url: request.url!,
                        json: ["success": true, "data": ["accessToken": "foreground-token", "refreshToken": "rotated"]],
                        headers: ["Set-Cookie": "refreshToken=rotated; Path=/; HttpOnly"]
                    )
                }
                if path == "/auth/info", request.value(forHTTPHeaderField: "Authorization") == "Bearer foreground-token" {
                    return httpResponse(status: 200, url: request.url!, json: [
                        "success": true,
                        "data": [
                            "userId": "user-1",
                            "profile": ["name": "Foreground User"]
                        ]
                    ])
                }
                if path == "/walkcalc/home/summary" {
                    return httpResponse(status: 200, url: request.url!, json: ["success": true, "data": ["totalBalance": "0"]])
                }
                if path == "/walkcalc/groups/my" {
                    return httpResponse(status: 200, url: request.url!, json: ["success": true, "data": []])
                }
                return httpResponse(status: 500, url: request.url!)
            }

            let store = WalkcalcStore()
            store.token = "expired-token"
            store.user = UserProfile(uuid: "user-1", name: "Old User", avatar: "")
            store.finishStartup(.authenticated)
            await store.handleForegroundActivation()

            expect(store.token, equals: Optional("foreground-token"), prefix: "auth-session-foreground-token")
            expect(store.user?.name, equals: Optional("Foreground User"), prefix: "auth-session-foreground-user")
            expect(calls.paths.contains("/auth/refreshToken"), equals: true, prefix: "auth-session-foreground-refresh-called")
            expect(calls.paths.contains("/walkcalc/home/summary"), equals: true, prefix: "auth-session-foreground-home-called")
            expect(calls.paths.contains("/walkcalc/groups/my"), equals: true, prefix: "auth-session-foreground-groups-called")
        }
    }

    private static func verifyMissingRefreshCredentialFailsAsAuthRefresh() async {
        await withMockProtocol { calls in
            NativeAuthSession.clearAuthCookies(baseURL: APIClient().baseURL, webBaseURL: APIClient().webBaseURL)
            MockURLProtocol.requestHandler = { request in
                calls.append((request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization")))
                return httpResponse(status: 401, url: request.url!)
            }

            do {
                _ = try await APIClient().userInfo(token: "expired-token")
                assertionFailure("auth-session-missing-refresh: expected authRefresh")
            } catch let error as APIClientError {
                expect(error.kind, equals: .authRefresh, prefix: "auth-session-missing-refresh-kind")
            } catch {
                assertionFailure("auth-session-missing-refresh: unexpected error \(error)")
            }
            expect(calls.paths, equals: ["/auth/info"], prefix: "auth-session-missing-refresh-no-refresh-call")
        }
    }

    private static func verifyTransportFailureRemainsNonAuth() async {
        await withMockProtocol { _ in
            MockURLProtocol.requestHandler = { _ in
                throw URLError(.notConnectedToInternet)
            }

            do {
                _ = try await APIClient().userInfo(token: "token")
                assertionFailure("auth-session-transport: expected transport error")
            } catch let error as APIClientError {
                expect(error.kind, equals: .transport, prefix: "auth-session-transport-kind")
            } catch {
                assertionFailure("auth-session-transport: unexpected error \(error)")
            }
        }
    }

    private static func withMockProtocol(_ operation: (_ calls: AuthSessionCallRecorder) async -> Void) async {
        let calls = AuthSessionCallRecorder()
        URLProtocol.registerClass(MockURLProtocol.self)
        defer {
            MockURLProtocol.requestHandler = nil
            URLProtocol.unregisterClass(MockURLProtocol.self)
            NativeAuthSession.clearAuthCookies(baseURL: APIClient().baseURL, webBaseURL: APIClient().webBaseURL)
        }
        await operation(calls)
    }

    private static func makeCookie(name: String, value: String, domain: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ])
    }

    private static func httpResponse(status: Int, url: URL, json: [String: Any] = [:], headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        let data = json.isEmpty ? Data() : (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (response, data)
    }

    private static func jsonBody(from request: URLRequest) -> [String: Any] {
        guard let data = request.httpBody ?? data(from: request.httpBodyStream),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func data(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }
}

private final class AuthSessionCallRecorder {
    private(set) var values: [(path: String, authorization: String?)] = []

    func append(_ value: (path: String, authorization: String?)) {
        guard !value.path.isEmpty else { return }
        values.append(value)
    }

    var paths: [String] {
        values.map(\.path)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "127.0.0.1"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
#endif
