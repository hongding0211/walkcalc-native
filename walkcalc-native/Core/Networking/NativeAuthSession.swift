import Foundation
import WebKit

struct NativeAuthSessionImportResult {
    let importedCookieNames: Set<String>

    var hasRefreshCredential: Bool {
        importedCookieNames.contains(NativeAuthSession.refreshCookieName)
    }
}

enum NativeAuthSession {
    static let accessCookieName = "accessToken"
    static let refreshCookieName = "refreshToken"
    private static let refreshTokenStoragePrefix = "walkcalc.refreshToken"

    private static let authCookieNames: Set<String> = [
        accessCookieName,
        refreshCookieName
    ]

    static func importAuthCookies(
        from cookieStore: WKHTTPCookieStore,
        baseURL: URL,
        webBaseURL: URL
    ) async -> NativeAuthSessionImportResult {
        let cookies = await allCookies(from: cookieStore)
        return importAuthCookies(cookies, baseURL: baseURL, webBaseURL: webBaseURL)
    }

    static func importAuthCookies(
        _ cookies: [HTTPCookie],
        baseURL: URL,
        webBaseURL: URL
    ) -> NativeAuthSessionImportResult {
        let candidateCookies = cookies.filter { cookie in
            authCookieNames.contains(cookie.name)
                && cookieMatchesAuthHost(cookie, baseURL: baseURL, webBaseURL: webBaseURL)
        }
        let importedNames = Set(candidateCookies.map(\.name))
        for cookie in candidateCookies {
            persist(cookie, for: baseURL, webBaseURL: webBaseURL)
            if cookie.name == refreshCookieName {
                storeRefreshToken(cookie.value, for: baseURL)
            }
        }
        return NativeAuthSessionImportResult(importedCookieNames: importedNames)
    }

    static func storeRefreshToken(_ refreshToken: String, for baseURL: URL) {
        guard !refreshToken.isEmpty else { return }
        UserDefaults.standard.set(refreshToken, forKey: refreshTokenStorageKey(for: baseURL))
    }

    static func refreshToken(for baseURL: URL) -> String? {
        guard let token = UserDefaults.standard.string(forKey: refreshTokenStorageKey(for: baseURL)),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    static func hasRefreshCredential(for baseURL: URL) -> Bool {
        guard let host = baseURL.host else { return false }
        let hasCookie = HTTPCookieStorage.shared.cookies?
            .contains { cookie in
                cookie.name == refreshCookieName
                    && cookieMatches(host: host, cookieDomain: cookie.domain)
                    && !isExpired(cookie)
            } ?? false
        return hasCookie || refreshToken(for: baseURL) != nil
    }

    static func clearAuthCookies(baseURL: URL, webBaseURL: URL) {
        let hosts = [baseURL.host, webBaseURL.host].compactMap { $0 }
        HTTPCookieStorage.shared.cookies?
            .filter { cookie in
                authCookieNames.contains(cookie.name)
                    && hosts.contains { cookieMatches(host: $0, cookieDomain: cookie.domain) || shouldDuplicateLoopbackCookie(cookieHost: cookie.domain, targetHost: $0) }
            }
            .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        UserDefaults.standard.removeObject(forKey: refreshTokenStorageKey(for: baseURL))
        UserDefaults.standard.removeObject(forKey: refreshTokenStorageKey(for: webBaseURL))
    }

    private static func refreshTokenStorageKey(for baseURL: URL) -> String {
        guard let host = baseURL.host else { return refreshTokenStoragePrefix }
        return "\(refreshTokenStoragePrefix).\(host)"
    }

    private static func allCookies(from cookieStore: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func persist(_ cookie: HTTPCookie, for baseURL: URL, webBaseURL: URL) {
        HTTPCookieStorage.shared.setCookie(cookie)
        guard let apiHost = baseURL.host,
              shouldDuplicateLoopbackCookie(cookieHost: cookie.domain, targetHost: apiHost),
              let apiCookie = duplicate(cookie, domain: apiHost) else {
            return
        }
        HTTPCookieStorage.shared.setCookie(apiCookie)
    }

    private static func duplicate(_ cookie: HTTPCookie, domain: String) -> HTTPCookie? {
        var properties = cookie.properties ?? [:]
        properties[.domain] = domain
        properties[.path] = cookie.path
        properties[.name] = cookie.name
        properties[.value] = cookie.value
        if cookie.isSecure {
            properties[.secure] = "TRUE"
        }
        if cookie.isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }

    private static func cookieMatchesAuthHost(_ cookie: HTTPCookie, baseURL: URL, webBaseURL: URL) -> Bool {
        [baseURL.host, webBaseURL.host]
            .compactMap { $0 }
            .contains { host in
                cookieMatches(host: host, cookieDomain: cookie.domain)
                    || shouldDuplicateLoopbackCookie(cookieHost: cookie.domain, targetHost: host)
            }
    }

    private static func cookieMatches(host: String, cookieDomain: String) -> Bool {
        let domain = cookieDomain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix(".\(domain)")
    }

    private static func shouldDuplicateLoopbackCookie(cookieHost: String, targetHost: String) -> Bool {
        isLoopback(cookieHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))) && isLoopback(targetHost)
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func isExpired(_ cookie: HTTPCookie) -> Bool {
        guard let expiresDate = cookie.expiresDate else { return false }
        return expiresDate <= Date()
    }
}
