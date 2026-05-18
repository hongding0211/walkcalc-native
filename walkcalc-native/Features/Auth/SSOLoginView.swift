import SwiftUI
import WebKit
import OSLog

struct SSOLoginView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @State private var hasVisitedGithub = false
    var onToken: (String) -> Void

    private let authSessionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "walkcalc-native", category: "AuthSession")

    var body: some View {
        WebView(url: store.api.loginURL(), usesPersistentDataStore: false, onToken: { url, cookieStore in
            if isGithubURL(url) {
                hasVisitedGithub = true
                return
            }
            if url.absoluteString.hasPrefix(store.api.redirectPrefix()),
               let token = token(from: url) {
                completeLogin(with: token, refreshToken: refreshToken(from: url), cookieStore: cookieStore)
            }
        }, onFinish: { url, cookieStore in
            guard hasVisitedGithub,
                  isAuthHost(url),
                  shouldCompleteFromCookie(afterFinishing: url) else { return }
            cookieStore.getAllCookies { cookies in
                guard let token = cookies.first(where: { $0.name == "accessToken" })?.value else {
                    return
                }
                completeLogin(
                    with: token,
                    refreshToken: cookies.first(where: { $0.name == NativeAuthSession.refreshCookieName })?.value,
                    cookies: cookies
                )
            }
        })
    }

    private func completeLogin(with token: String, refreshToken: String? = nil, cookies: [HTTPCookie]? = nil, cookieStore: WKHTTPCookieStore? = nil) {
        let api = store.api
        if let cookies {
            Task {
                finishLogin(
                    token: token,
                    refreshToken: refreshToken,
                    importResult: NativeAuthSession.importAuthCookies(cookies, baseURL: api.baseURL, webBaseURL: api.webBaseURL)
                )
            }
            return
        }

        guard let cookieStore else {
            Task {
                finishLogin(token: token, refreshToken: refreshToken, importResult: NativeAuthSessionImportResult(importedCookieNames: []))
            }
            return
        }

        Task {
            let importResult = await NativeAuthSession.importAuthCookies(from: cookieStore, baseURL: api.baseURL, webBaseURL: api.webBaseURL)
            finishLogin(token: token, refreshToken: refreshToken, importResult: importResult)
        }
    }

    private func finishLogin(token: String, refreshToken: String?, importResult: NativeAuthSessionImportResult) {
        if let refreshToken, !refreshToken.isEmpty {
            NativeAuthSession.storeRefreshToken(refreshToken, for: store.api.baseURL)
        }
        if importResult.hasRefreshCredential || refreshToken?.isEmpty == false {
            authSessionLogger.info("Native auth session imported refresh credential")
        } else {
            authSessionLogger.notice("Native auth session completed without importable refresh credential")
        }
        DispatchQueue.main.async {
            onToken(token)
        }
    }

    private func isAuthHost(_ url: URL) -> Bool {
        guard let host = url.host,
              let authHost = store.api.webBaseURL.host else {
            return false
        }
        return host == authHost
    }

    private func isGithubURL(_ url: URL) -> Bool {
        url.host == "github.com"
    }

    private func shouldCompleteFromCookie(afterFinishing url: URL) -> Bool {
        guard !url.path.hasPrefix("/api/auth/github"),
              !url.path.hasPrefix("/sso/login") else {
            return false
        }
        return true
    }

    private func token(from url: URL) -> String? {
        if let fragment = url.fragment {
            return queryValue(fragment, key: "accessToken")
                ?? queryValue(fragment, key: "token")
                ?? fragment.components(separatedBy: "&").first?.removingPercentEncoding
        }
        guard let query = url.query else {
            return nil
        }
        return queryValue(query, key: "accessToken") ?? queryValue(query, key: "token")
    }

    private func refreshToken(from url: URL) -> String? {
        if let fragment = url.fragment {
            return queryValue(fragment, key: "refreshToken")
        }
        guard let query = url.query else {
            return nil
        }
        return queryValue(query, key: "refreshToken")
    }

    private func queryValue(_ source: String, key: String) -> String? {
        source
            .split(separator: "&")
            .compactMap { item -> (String, String)? in
                let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
            .first(where: { $0.0 == key })?
            .1
            .removingPercentEncoding
    }
}

struct WebView: UIViewRepresentable {
    var url: URL
    var token: String?
    var injectAuthCookie = false
    var usesPersistentDataStore = true
    var onToken: ((URL, WKHTTPCookieStore) -> Void)?
    var onFinish: ((URL, WKHTTPCookieStore) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onFinish: onFinish)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = usesPersistentDataStore && !injectAuthCookie ? .default() : .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "authCallback")
        if !usesPersistentDataStore && !injectAuthCookie {
            clearSharedCookies(for: url)
        }
        var request = URLRequest(url: url)
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if injectAuthCookie {
                configuration.userContentController.addUserScript(authForwardingScript(token: token))
            }
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(request)
        return webView
    }

    private func clearSharedCookies(for url: URL) {
        guard let host = url.host else { return }
        HTTPCookieStorage.shared.cookies?
            .filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return host == domain || host.hasSuffix(".\(domain)")
            }
            .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    private func authForwardingScript(token: String) -> WKUserScript {
        let encodedToken = Self.javascriptStringLiteral(token)
        let source = """
        (() => {
          const nativeAccessToken = \(encodedToken);
          const shouldAuthorize = (input) => {
            try {
              const rawUrl = input instanceof Request ? input.url : input;
              const url = new URL(rawUrl, window.location.href);
              return url.origin === window.location.origin && url.pathname.startsWith('/api/');
            } catch {
              return false;
            }
          };
          const authorizedHeaders = (headers) => {
            const nextHeaders = new Headers(headers || undefined);
            nextHeaders.set('Authorization', `Bearer ${nativeAccessToken}`);
            return nextHeaders;
          };
          const originalFetch = window.fetch;
          window.fetch = (input, init = {}) => {
            if (shouldAuthorize(input)) {
              init = { ...init, headers: authorizedHeaders(init.headers || (input instanceof Request ? input.headers : undefined)) };
            }
            return originalFetch(input, init);
          };
          const originalOpen = XMLHttpRequest.prototype.open;
          const originalSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(method, requestUrl, ...args) {
            this.__nativeShouldAuthorize = shouldAuthorize(requestUrl);
            return originalOpen.call(this, method, requestUrl, ...args);
          };
          XMLHttpRequest.prototype.send = function(...args) {
            if (this.__nativeShouldAuthorize) {
              this.setRequestHeader('Authorization', `Bearer ${nativeAccessToken}`);
            }
            return originalSend.apply(this, args);
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "authCallback")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onToken: ((URL, WKHTTPCookieStore) -> Void)?
        var onFinish: ((URL, WKHTTPCookieStore) -> Void)?

        init(onToken: ((URL, WKHTTPCookieStore) -> Void)?, onFinish: ((URL, WKHTTPCookieStore) -> Void)?) {
            self.onToken = onToken
            self.onFinish = onFinish
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "authCallback",
                  let urlString = message.body as? String,
                  let url = URL(string: urlString) else {
                return
            }
            // Script messages do not expose a WKWebView; native callbacks use the page URL only.
            onToken?(url, WKWebsiteDataStore.default().httpCookieStore)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                onToken?(url, webView.configuration.websiteDataStore.httpCookieStore)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("localStorage.clear()")
            if let url = webView.url {
                onFinish?(url, webView.configuration.websiteDataStore.httpCookieStore)
            }
        }
    }
}
