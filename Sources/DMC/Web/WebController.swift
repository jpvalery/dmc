import AppKit
import Combine
import WebKit

/// A `WKWebView` that offers "Open Link in New Tab" in its context menu.
///
/// Rather than racing a JavaScript `contextmenu` listener to learn the link URL, this retitles
/// WebKit's own "Open Link in New Window" item and leaves its action alone. WebKit then hands us
/// the URL through `createWebViewWith`, which is exactly where a new tab gets opened — no race,
/// and no guessing what was under the cursor.
final class DMCWebView: WKWebView {
    /// Set for exactly one `createWebViewWith` call, so only a deliberate menu choice opens a tab.
    var pendingContextNewTab = false

    private var wrappedAction: Selector?
    private weak var wrappedTarget: AnyObject?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // The identifier is set at runtime even though the constant is absent from the
        // Command Line Tools headers; matching the raw string degrades harmlessly if it changes.
        for item in menu.items where item.identifier?.rawValue.contains("OpenLinkInNewWindow") == true {
            item.title = "Open Link in New Tab"
            wrappedAction = item.action
            wrappedTarget = item.target
            item.target = self
            item.action = #selector(openLinkInNewTab(_:))
        }
    }

    /// Record the intent, then hand off to WebKit's original action — which is what supplies the
    /// link URL, via `createWebViewWith`.
    @objc private func openLinkInNewTab(_ sender: NSMenuItem) {
        pendingContextNewTab = true
        if let wrappedAction {
            NSApp.sendAction(wrappedAction, to: wrappedTarget, from: sender)
        }
    }
}

/// Owns the one and only `WKWebView` for the session.
///
/// Held as a `@StateObject` above the pane so the view is created exactly once — rebuilding it
/// from `updateNSView` would reload the VTT on every pane resize.
@MainActor
final class WebController: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var urlText = ""
    @Published var title = ""

    let webView: WKWebView
    /// Set by `TabsModel`: (url, openInBackground).
    var onOpenInNewTab: ((URL, Bool) -> Void)?
    private let home: URL

    init(home: URL) {
        self.home = home

        let config = WKWebViewConfiguration()
        // Persistent store: the Wizards of the Coast login has to survive relaunches,
        // otherwise this is a daily-login tool instead of a one-time-login tool.
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = DMCWebView(frame: .zero, configuration: config)

        super.init()

        // customUserAgent stays nil on purpose. WebKit's default is a legitimate Safari UA,
        // which is the safest string to present to the WotC login and whatever bot
        // protection sits in front of it.
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.uiDelegate = self
        webView.navigationDelegate = self

        // Combine's KVO bridge rather than hand-rolled observers: it handles the delivery
        // thread for us and the cancellables live as long as the published properties.
        webView.publisher(for: \.canGoBack).receive(on: RunLoop.main).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).receive(on: RunLoop.main).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading).receive(on: RunLoop.main).assign(to: &$isLoading)
        webView.publisher(for: \.url)
            .map { $0?.absoluteString ?? "" }
            .receive(on: RunLoop.main)
            .assign(to: &$urlText)
        webView.publisher(for: \.title)
            .map { $0 ?? "" }
            .receive(on: RunLoop.main)
            .assign(to: &$title)

        load(home)
    }

    // MARK: - Navigation

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func goHome() { load(home) }

    func reloadOrStop() {
        if isLoading { webView.stopLoading() } else { webView.reload() }
    }

    /// Escape hatch: if anything renders wrong under WebKit, get the current page into the
    /// real browser rather than being stuck.
    func openInDefaultBrowser() {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    /// Give the page keyboard focus.
    ///
    /// System AutoFill — and therefore 1Password's native credential provider — is deliberately
    /// disabled inside WKWebView by WebKit, and the Associated Domains entitlement that would
    /// re-enable it requires controlling dndbeyond.com. 1Password's Universal Autofill (⌘\)
    /// works anyway, because it drives the accessibility APIs rather than a browser extension;
    /// it just needs a focused field, which this provides on launch.
    func focusPage() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.webView.window else { return }
            window.makeFirstResponder(self.webView)
        }
    }

    // MARK: - WKUIDelegate

    /// `target="_blank"`, `window.open`, and the retitled "Open Link in New Tab" all arrive
    /// here. Without this, such links silently do nothing — WKWebView's most commonly hit
    /// papercut. Cross-host navigation is *not* punted to the browser, because the WotC login
    /// flow leaves dndbeyond.com and must be able to come back.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        // Only an explicit "Open Link in New Tab" gets a tab. Plain `target="_blank"` loads in
        // place: D&D Beyond marks a lot of ordinary links that way, and opening a tab for each
        // is what made every click feel like it spawned one.
        let host = webView as? DMCWebView
        let explicit = host?.pendingContextNewTab ?? false
        host?.pendingContextNewTab = false

        if explicit, let onOpenInNewTab {
            onOpenInNewTab(url, false)
        } else {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    /// ⌘-click opens a background tab, the way a browser does. Deliberately *only* ⌘-click:
    /// `buttonNumber`'s convention is ambiguous here (AppKit numbers the right button 1, the DOM
    /// numbers the middle button 1), so testing it risked treating ordinary clicks as
    /// middle-clicks. Plain clicks always navigate in place.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command),
           let url = navigationAction.request.url,
           let onOpenInNewTab {
            onOpenInNewTab(url, true)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// DDB Maps uploads map images through a file input; without an open-panel handler the
    /// picker never appears and uploads look broken.
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
