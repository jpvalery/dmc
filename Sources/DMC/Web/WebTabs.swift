import Combine
import Foundation
import SwiftUI

@MainActor
final class WebTab: Identifiable, ObservableObject {
    let id = UUID()
    let controller: WebController

    init(url: URL) { controller = WebController(home: url) }

    /// Prefer the page title; fall back to the host so a loading tab still reads sensibly.
    var label: String {
        let title = controller.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return title }
        if let host = URL(string: controller.urlText)?.host() {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "New tab"
    }
}

@MainActor
final class TabsModel: ObservableObject {
    @Published private(set) var tabs: [WebTab] = []
    @Published var selectedID: WebTab.ID?
    /// When set, this tab is shown beside the selected one.
    @Published var secondaryID: WebTab.ID?

    /// Every tab shares `WKWebsiteDataStore.default()`, so one sign-in covers all of them —
    /// including across campaigns, which is what you want: same account, different game.
    init() {
        Vault.bootstrap()
        tabs = Self.savedURLs().map { makeTab($0) }
        if tabs.isEmpty { tabs = [makeTab(Home.url())] }
        selectedID = tabs.first?.id
    }

    private static func savedURLs() -> [URL] {
        guard let data = try? Data(contentsOf: Vault.tabsFile),
              let strings = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return strings.compactMap(URL.init(string:))
    }

    /// Swap in another campaign's pages. The old tabs' web views go with them.
    func reloadForCampaign() {
        tabs = Self.savedURLs().map { makeTab($0) }
        if tabs.isEmpty { tabs = [makeTab(Home.url())] }
        selectedID = tabs.first?.id
        secondaryID = nil
    }

    var selected: WebTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    var secondary: WebTab? {
        guard let secondaryID, secondaryID != selectedID else { return nil }
        return tabs.first { $0.id == secondaryID }
    }

    var isSplit: Bool { secondary != nil }

    /// Split with the next tab along, creating one if this is the only tab.
    func toggleSplit() {
        if isSplit { secondaryID = nil; return }
        if let current = tabs.firstIndex(where: { $0.id == selectedID }), tabs.count > 1 {
            secondaryID = tabs[(current + 1) % tabs.count].id
        } else {
            secondaryID = newTabInBackground().id
        }
    }

    func showBeside(_ id: WebTab.ID) {
        secondaryID = (id == selectedID) ? nil : id
    }

    @discardableResult
    func newTabInBackground(url: URL? = nil) -> WebTab {
        let tab = makeTab(url ?? Home.url())
        tabs.append(tab)
        persist()
        return tab
    }

    /// Every tab is built here so its "open in new tab" hook is wired — including tabs opened
    /// *by* another tab, which is why this is called recursively from inside the closure.
    private func makeTab(_ url: URL) -> WebTab {
        let tab = WebTab(url: url)
        tab.controller.onOpenInNewTab = { [weak self] linkURL, inBackground in
            guard let self else { return }
            let opened = self.makeTab(linkURL)
            if let anchor = self.tabs.firstIndex(where: { $0.id == tab.id }) {
                // Slot it next to its opener rather than at the far end, so a burst of
                // ⌘-clicks stays near the page they came from.
                self.tabs.insert(opened, at: anchor + 1)
            } else {
                self.tabs.append(opened)
            }
            if !inBackground { self.selectedID = opened.id }
            self.persist()
        }
        return tab
    }

    @discardableResult
    func newTab(url: URL? = nil) -> WebTab {
        let tab = makeTab(url ?? Home.url())
        tabs.append(tab)
        selectedID = tab.id
        persist()
        return tab
    }

    func close(_ id: WebTab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if secondaryID == id { secondaryID = nil }
        if selectedID == id {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
        persist()
    }

    func closeSelected() {
        if let selectedID { close(selectedID) }
    }

    func cycle(by offset: Int) {
        guard tabs.count > 1, let current = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        let next = (current + offset + tabs.count) % tabs.count
        selectedID = tabs[next].id
    }

    /// Remember which pages were open, so a relaunch mid-session doesn't lose the DM's place.
    /// Stored per campaign, next to that campaign's scenes.
    func persist() {
        let urls = tabs.map(\.controller.urlText).filter { !$0.isEmpty }
        guard let data = try? JSONEncoder().encode(urls) else { return }
        try? data.write(to: Vault.tabsFile, options: .atomic)
    }
}

struct TabBar: View {
    @ObservedObject var model: TabsModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.tabs) { tab in
                        TabChip(tab: tab,
                                isSelected: tab.id == model.selectedID,
                                isSecondary: tab.id == model.secondaryID && model.isSplit,
                                canClose: model.tabs.count > 1,
                                onSelect: { model.selectedID = tab.id },
                                onSendRight: { model.showBeside(tab.id) },
                                onClose: { model.close(tab.id) })
                    }
                }
                .padding(.horizontal, 6)
            }

            Button { model.newTab() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .help("New tab  ⌘T")
        }
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TabChip: View {
    @ObservedObject var tab: WebTab
    let isSelected: Bool
    let isSecondary: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onSendRight: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            if isSecondary {
                Image(systemName: "rectangle.righthalf.filled")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
            if tab.controller.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 10, height: 10)
            }
            Text(tab.label)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            if canClose && (hovering || isSelected) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Close tab  ⌘W")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minWidth: 90, maxWidth: 190)
        .background(isSelected || isSecondary ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? Color.accentColor : (isSecondary ? Color.accentColor.opacity(0.45) : Color.clear))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(isSecondary ? "Remove from split" : "Show beside current", action: onSendRight)
            if canClose { Button("Close tab", action: onClose) }
        }
        .help(tab.label + (isSecondary ? "  (right pane)" : ""))
    }
}
