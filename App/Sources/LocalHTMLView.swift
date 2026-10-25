import AppKit
import WebKit

/// Widoki HTML z treścią niezaufaną (dane z bazy, cudze pliki raportów): bez JavaScriptu i bez nawigacji poza treść
/// wczytaną przez `loadHTMLString(_:baseURL: nil)`. CSP w dokumencie (`LocalHTML`) nie obejmuje nawigacji — bez tego
/// `<meta http-equiv="refresh">` albo kliknięty odnośnik przeniósłby widok na zdalną stronę.
extension WKWebView {
    static func localHTML(frame: NSRect = .zero) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: frame, configuration: config)
        view.navigationDelegate = LocalHTMLNavigationGuard.shared
        return view
    }
}

/// Przepuszcza tylko treść z `loadHTMLString` (about:blank); odnośniki, przekierowania i odświeżenia są blokowane.
@MainActor
final class LocalHTMLNavigationGuard: NSObject, WKNavigationDelegate {
    static let shared = LocalHTMLNavigationGuard()

    static func allows(_ action: WKNavigationAction) -> Bool {
        let url = action.request.url
        return url == nil || url?.absoluteString == "about:blank"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        Self.allows(navigationAction) ? .allow : .cancel
    }
}
