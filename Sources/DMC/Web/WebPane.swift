import SwiftUI
import WebKit

/// Hosts an existing `WKWebView`. `makeNSView` hands back the view the controller already owns
/// and `updateNSView` does nothing — rebuilding it would reload the page on every pane resize.
struct WebViewHost: NSViewRepresentable {
    let controller: WebController

    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct WebPane: View {
    @ObservedObject var tabs: TabsModel
    @Binding var railCollapsed: Bool
    @Binding var notesHidden: Bool

    @AppStorage("web.splitFraction") private var splitFraction: Double = 0.5
    @State private var dragBase: Double?

    var body: some View {
        VStack(spacing: 0) {
            if tabs.tabs.count > 1 {
                TabBar(model: tabs)
                Divider()
            }

            if let primary = tabs.selected {
                WebNavBar(controller: primary.controller,
                          tabs: tabs,
                          railCollapsed: $railCollapsed,
                          notesHidden: $notesHidden)
                Divider()

                if let secondary = tabs.secondary {
                    splitBody(primary: primary, secondary: secondary)
                } else {
                    page(primary)
                }
            }
        }
    }

    /// Background tabs keep their WKWebView alive inside their controller, so moving a tab
    /// between panes — or out of a split entirely — preserves scroll position and game state.
    /// The .id forces SwiftUI to swap in the right tab's view rather than reuse the old one.
    private func page(_ tab: WebTab) -> some View {
        WebViewHost(controller: tab.controller)
            .id(tab.id)
            .onAppear { tab.controller.focusPage() }
    }

    private func splitBody(primary: WebTab, secondary: WebTab) -> some View {
        GeometryReader { geo in
            let total = geo.size.width
            let minPane: CGFloat = 280
            let left = (total * splitFraction).clamped(minPane, max(minPane, total - minPane - 1))

            HStack(spacing: 0) {
                page(primary).frame(width: left)

                PaneDivider(
                    onDrag: { dx in
                        let base = dragBase ?? splitFraction
                        if dragBase == nil { dragBase = base }
                        let target = (base * total + dx).clamped(minPane, max(minPane, total - minPane - 1))
                        splitFraction = target / total
                    },
                    onEnd: { dragBase = nil }
                )

                VStack(spacing: 0) {
                    SecondaryBar(tab: secondary, tabs: tabs)
                    Divider()
                    page(secondary)
                }
            }
        }
    }
}

/// A compact bar for the right-hand pane. The main nav bar drives the left pane; this keeps the
/// two symmetrical enough to use without doubling the chrome.
private struct SecondaryBar: View {
    @ObservedObject var tab: WebTab
    @ObservedObject var tabs: TabsModel

    var body: some View {
        HStack(spacing: 6) {
            Button { tab.controller.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!tab.controller.canGoBack)
            Button { tab.controller.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!tab.controller.canGoForward)
            Button { tab.controller.reloadOrStop() } label: {
                Image(systemName: tab.controller.isLoading ? "xmark" : "arrow.clockwise")
            }

            Text(tab.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if tab.controller.isLoading { ProgressView().controlSize(.small) }

            Button { tabs.secondaryID = nil } label: { Image(systemName: "xmark.circle") }
                .help("Close the split")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
