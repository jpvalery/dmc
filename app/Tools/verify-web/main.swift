import AppKit
import WebKit

/// `Home` lives in `RootView.swift`; the web layer only needs its URL.
enum Home {
    static func url() -> URL { URL(string: "https://www.dndbeyond.com/my-campaigns")! }
}

/// Restored tabs: only the first loads at launch, the rest wait to be shown — and waiting must
/// not lose them from the saved list. (`goHome` is not covered: it needs the network.)
@main
struct Probe {
    @MainActor
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        UserDefaults.standard.set(CommandLine.arguments[1], forKey: "vault.path")
        Vault.bootstrap()
        _ = NSApplication.shared

        var fails = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("  \(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { fails += 1 }
        }
        func waitUntil(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .seconds(seconds)
            while ContinuousClock.now < deadline {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(25))
            }
            return condition()
        }

        // Local pages, so nothing here touches the network.
        let dir = URL(filePath: CommandLine.arguments[1])
        var pages: [String] = []
        for name in ["one", "two", "three"] {
            let url = dir.appending(path: "\(name).html")
            try? "<html><title>\(name)</title><body>\(name)</body></html>".write(to: url, atomically: true, encoding: .utf8)
            pages.append(url.absoluteString)
        }
        JSONStore.save(pages, to: Vault.tabsFile)

        let tabs = TabsModel()
        check("all three tabs are restored", tabs.tabs.count == 3)
        let firstLoads = await waitUntil { tabs.tabs[0].controller.webView.url != nil }
        check("the first tab loads at launch", firstLoads)
        try? await Task.sleep(for: .milliseconds(500))
        check("the others have not loaded",
              tabs.tabs[1].controller.webView.url == nil && tabs.tabs[2].controller.webView.url == nil)
        check("but still show their address", tabs.tabs[1].controller.urlText == pages[1])
        check("and have a readable label", tabs.tabs[1].label == "New tab" || !tabs.tabs[1].label.isEmpty,
              tabs.tabs[1].label)

        tabs.persist()
        if case .ok(let saved) = JSONStore.load([String].self, from: Vault.tabsFile) {
            check("saving with tabs still unloaded keeps every tab", saved == pages, "\(saved.count) saved")
        } else {
            check("saving with tabs still unloaded keeps every tab", false)
        }

        tabs.tabs[1].controller.loadIfNeeded()
        let secondLoads = await waitUntil { tabs.tabs[1].controller.webView.url != nil }
        check("showing a tab loads it", secondLoads)
        check("and it reports its page", await waitUntil { tabs.tabs[1].controller.title == "two" },
              tabs.tabs[1].controller.title)
        tabs.tabs[1].controller.loadIfNeeded()
        check("asking again does nothing", tabs.tabs[1].controller.webView.url?.absoluteString == pages[1])

        // A campaign switch restores again, with the same rule.
        tabs.reloadForCampaign()
        check("a campaign switch restores lazily too", tabs.tabs.count == 3 && tabs.tabs[2].controller.webView.url == nil)

        print(fails == 0 ? "\n  all web checks pass" : "\n  \(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}
