#if DEBUG
import Foundation

enum AuthSessionVerification {
    static func assertAllCasesPass() async {
        await verifyCookieImportAndClear()
        await verifyRefreshRetryPersistsAccessToken()
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

    private static func expect<T: Equatable>(_ actual: T, equals expected: T, prefix: String) {
        assert(actual == expected, "\(prefix): expected '\(expected)', got '\(actual)'")
    }
}

private final class AuthSessionCallRecorder {
    private(set) var values: [(path: String, authorization: String?)] = []

    func append(_ value: (path: String, authorization: String?)) {
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
