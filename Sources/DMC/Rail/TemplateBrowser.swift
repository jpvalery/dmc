import Combine
import SwiftUI

/// Fetches the audio a template needs, one file at a time.
@MainActor
final class TemplateFetcher: ObservableObject {
    @Published private(set) var active: String?
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var failures: [String] = []

    var isBusy: Bool { active != nil }

    /// Downloads whatever the template is missing, then reports whether the vault is complete.
    func fetch(_ template: SceneTemplate) async -> Bool {
        let missing = template.missingFiles
        guard !missing.isEmpty else { return true }

        total = missing.count
        done = 0
        failures = []
        defer { active = nil }

        for path in missing {
            active = (path as NSString).lastPathComponent
            guard let remote = template.downloadURL(for: path) else {
                failures.append(path)
                continue
            }
            let destination = Vault.audio.appending(path: path)
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                let (temp, response) = try await URLSession.shared.download(from: remote)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    try? FileManager.default.removeItem(at: temp)
                    failures.append(path)
                    continue
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temp, to: destination)
                done += 1
            } catch {
                failures.append(path)
            }
            // One small server, one file at a time.
            try? await Task.sleep(for: .milliseconds(80))
        }
        return failures.isEmpty
    }
}

struct TemplateBrowser: View {
    @ObservedObject var library: TemplateLibrary
    @ObservedObject var store: SceneStore
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var fetcher = TemplateFetcher()
    @State private var search = ""
    @State private var justAdded: Set<String> = []

    private var matches: [SceneTemplate] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return library.templates }
        return library.templates.filter {
            ($0.name + " " + $0.tags.joined(separator: " ")).lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Scene templates").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TextField("Search templates and tags", text: $search)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
    }

    private var list: some View {
        List(matches) { template in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: template.symbol)
                    .font(.system(size: 16))
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(.callout.weight(.medium))
                    Text(summary(for: template))
                        .font(.caption).foregroundStyle(.secondary)
                    if !template.tags.isEmpty {
                        Text(template.tags.prefix(6).joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if justAdded.contains(template.name) {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly).foregroundStyle(.green)
                } else {
                    Button("Add") { Task { await add(template) } }
                        .disabled(fetcher.isBusy)
                }
            }
            .padding(.vertical, 3)
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if fetcher.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading \(fetcher.active ?? "") — \(fetcher.done) of \(fetcher.total)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !fetcher.failures.isEmpty {
                Label("\(fetcher.failures.count) file(s) could not be downloaded",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Text("Adding a template copies it into this campaign; the template stays here, so "
                     + "you can add it again after deleting.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Add all") {
                    Task { for t in matches where !justAdded.contains(t.name) { await add(t) } }
                }
                .disabled(fetcher.isBusy || matches.isEmpty)
            }

            if !library.note.isEmpty {
                Text(library.note).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    private func summary(for template: SceneTemplate) -> String {
        var parts: [String] = []
        if template.loopCount > 0 { parts.append("\(template.loopCount) looping") }
        if template.sporadicCount > 0 { parts.append("\(template.sporadicCount) sporadic") }
        let missing = template.missingFiles.count
        if missing > 0 { parts.append("\(missing) file\(missing == 1 ? "" : "s") to download") }
        return parts.joined(separator: " · ")
    }

    private func add(_ template: SceneTemplate) async {
        // Fetch first so a scene is never added with layers pointing at nothing.
        let complete = await fetcher.fetch(template)
        guard complete else { return }
        store.upsert(template.makeScene())
        justAdded.insert(template.name)
        onAdded()
    }
}
