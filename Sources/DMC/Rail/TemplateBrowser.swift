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
    func fetch(_ template: some AudioTemplate) async -> Bool {
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
    @ObservedObject var effects: EffectStore
    let onAdded: () -> Void

    private enum Kind: String, CaseIterable { case scenes = "Scenes", effects = "Effects" }
    @State private var kind: Kind = .scenes

    @StateObject private var fetcher = TemplateFetcher()
    @State private var search = ""
    @State private var justAdded: Set<String> = []

    private var needle: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    private var matches: [SceneTemplate] {
        guard !needle.isEmpty else { return library.templates }
        return library.templates.filter {
            ($0.name + " " + $0.tags.joined(separator: " ")).lowercased().contains(needle)
        }
    }

    private var effectMatches: [EffectTemplate] {
        guard !needle.isEmpty else { return library.effectTemplates }
        return library.effectTemplates.filter {
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
        .frame(minWidth: 720, minHeight: 560)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Templates").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Search templates and tags", text: $search)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
    }

    @ViewBuilder
    private var list: some View {
        switch kind {
        case .scenes:
            List(matches) { template in
                row(symbol: template.symbol, name: template.name,
                    detail: summary(for: template), tags: template.tags,
                    added: justAdded.contains("scene:" + template.name)) {
                    Task { await addScene(template) }
                }
            }
            .listStyle(.inset)
        case .effects:
            List(effectMatches) { template in
                row(symbol: template.symbol, name: template.name,
                    detail: effectSummary(for: template), tags: template.tags,
                    added: justAdded.contains("effect:" + template.name)) {
                    Task { await addEffect(template) }
                }
            }
            .listStyle(.inset)
        }
    }

    private func row(symbol: String, name: String, detail: String, tags: [String],
                     added: Bool, add: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.callout.weight(.medium))
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if !tags.isEmpty {
                    Text(tags.prefix(6).joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if added {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly).foregroundStyle(.green)
            } else {
                Button("Add", action: add).disabled(fetcher.isBusy)
            }
        }
        .padding(.vertical, 3)
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
                    Task {
                        switch kind {
                        case .scenes:
                            for t in matches where !justAdded.contains("scene:" + t.name) {
                                await addScene(t)
                            }
                        case .effects:
                            for t in effectMatches where !justAdded.contains("effect:" + t.name) {
                                await addEffect(t)
                            }
                        }
                    }
                }
                .disabled(fetcher.isBusy || (kind == .scenes ? matches.isEmpty : effectMatches.isEmpty))
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

    private func effectSummary(for template: EffectTemplate) -> String {
        var parts: [String] = []
        if template.takeCount > 1 { parts.append("\(template.takeCount) takes") }
        let missing = template.missingFiles.count
        if missing > 0 { parts.append("\(missing) file\(missing == 1 ? "" : "s") to download") }
        if !template.credit.isEmpty { parts.append(template.credit) }
        return parts.joined(separator: " · ")
    }

    private func addScene(_ template: SceneTemplate) async {
        // Fetch first so a scene is never added with layers pointing at nothing.
        guard await fetcher.fetch(template) else { return }
        store.upsert(template.makeScene())
        justAdded.insert("scene:" + template.name)
        onAdded()
    }

    private func addEffect(_ template: EffectTemplate) async {
        guard await fetcher.fetch(template) else { return }
        effects.upsert(template.makeEffect())
        justAdded.insert("effect:" + template.name)
        onAdded()
    }
}


enum TemplateWindow {
    static let id = "templates"
}
