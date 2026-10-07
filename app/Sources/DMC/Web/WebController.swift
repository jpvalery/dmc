import AppKit
import Observation
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

/// Owns one tab's `WKWebView`.
///
/// Held by its `WebTab` so the view is created exactly once — rebuilding it from `updateNSView`
/// would reload the VTT on every pane resize.
///
/// A tab restored from the last session is created *unloaded*: its address is remembered and
/// shown, but the page is not fetched until the tab is first displayed. Loading every tab at
/// launch started a web-content process per tab, each running D&D Beyond, before the DM had
/// looked at any but the first.
@MainActor
@Observable final class WebController: NSObject, WKUIDelegate, WKNavigationDelegate {
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var urlText = ""
    var title = ""

    let webView: WKWebView
    /// Set by `TabsModel`: (url, openInBackground).
    @ObservationIgnored var onOpenInNewTab: ((URL, Bool) -> Void)?
    /// Set while the tab has an address but has not been loaded yet.
    @ObservationIgnored private var pendingURL: URL?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(url: URL, loadNow: Bool = true) {
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

        // KVO on the web view, hopped to the main queue so the observable properties are only
        // ever written from the main actor.
        observations = [
            webView.observe(\.canGoBack) { [weak self] view, _ in
                let value = view.canGoBack
                Task { @MainActor in self?.canGoBack = value }
            },
            webView.observe(\.canGoForward) { [weak self] view, _ in
                let value = view.canGoForward
                Task { @MainActor in self?.canGoForward = value }
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                let value = view.isLoading
                Task { @MainActor in self?.isLoading = value }
            },
            webView.observe(\.url) { [weak self] view, _ in
                let value = view.url?.absoluteString
                // An unloaded tab keeps showing its remembered address.
                Task { @MainActor in if let value { self?.urlText = value } }
            },
            webView.observe(\.title) { [weak self] view, _ in
                let value = view.title ?? ""
                Task { @MainActor in self?.title = value }
            },
        ]

        if loadNow {
            load(url)
        } else {
            pendingURL = url
            urlText = url.absoluteString
        }
    }

    /// Fetches the remembered page the first time the tab is shown. Does nothing afterwards.
    func loadIfNeeded() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        load(url)
    }

    /// The address to remember across launches — the live one, or the one still waiting to load.
    var persistedURL: String { pendingURL?.absoluteString ?? urlText }

    // MARK: - Navigation

    func load(_ url: URL) {
        pendingURL = nil
        webView.load(URLRequest(url: url))
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    /// The campaigns page — not whatever this tab was first opened on, which for a tab restored
    /// from the last session is wherever it happened to be at quit.
    func goHome() { load(Home.url()) }

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
