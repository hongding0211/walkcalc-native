import SwiftUI
import WebKit

struct SSOLoginView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.dismiss) private var dismiss
    var onToken: (String) -> Void

    var body: some View {
        NavigationStack {
            WebView(url: store.api.loginURL()) { url in
                guard url.absoluteString.hasPrefix(store.api.redirectPrefix()),
                      let token = token(from: url) else {
                    return
                }
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
                    DispatchQueue.main.async {
                        onToken(token)
                    }
                }
            }
            .navigationTitle(L("Login"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
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
    var onToken: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        var request = URLRequest(url: url)
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if injectAuthCookie {
                let script = """
                document.cookie = 'accessToken=\(token); path=/; SameSite=Lax';
                true;
                """
                let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                configuration.userContentController.addUserScript(userScript)
            }
        }
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onToken: ((URL) -> Void)?

        init(onToken: ((URL) -> Void)?) {
            self.onToken = onToken
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                onToken?(url)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("localStorage.clear()")
        }
    }
}
