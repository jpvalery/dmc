import SwiftUI

struct WebNavBar: View {
    @ObservedObject var controller: WebController
    @ObservedObject var tabs: TabsModel
    @Binding var railCollapsed: Bool
    @Binding var notesHidden: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button { railCollapsed.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .help("\(railCollapsed ? "Expand" : "Collapse") the scene rail  ⌘⌥1")

            Divider().frame(height: 14)

            Button(action: controller.goBack) { Image(systemName: "chevron.left") }
                .disabled(!controller.canGoBack)
                .help("Back  ⌘[")

            Button(action: controller.goForward) { Image(systemName: "chevron.right") }
                .disabled(!controller.canGoForward)
                .help("Forward  ⌘]")

            Button(action: controller.reloadOrStop) {
                Image(systemName: controller.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(controller.isLoading ? "Stop" : "Reload  ⌘R")

            Button(action: controller.goHome) { Image(systemName: "house") }
                .help("Campaigns  ⌘⇧H")

            Text(controller.urlText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            if controller.isLoading {
                ProgressView().controlSize(.small)
            }

            Button { tabs.toggleSplit() } label: {
                Image(systemName: tabs.isSplit ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }
            .help(tabs.isSplit ? "Close the split  ⌘⌥S" : "Show two pages side by side  ⌘⌥S")

            Button { tabs.newTab(url: URL(string: controller.urlText)) } label: {
                Image(systemName: "plus.square.on.square")
            }
            .help("Duplicate this page into a new tab")

            Button(action: controller.openInDefaultBrowser) {
                Image(systemName: "safari")
            }
            .help("Open this page in the default browser")

            Divider().frame(height: 14)

            Button { notesHidden.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .help("\(notesHidden ? "Show" : "Hide") notes  ⌘⌥2")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: 32)
    }
}
