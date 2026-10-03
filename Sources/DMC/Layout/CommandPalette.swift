import SwiftUI

/// One thing the palette can do.
struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let group: String
    let run: () -> Void
}

/// ⌘K: type a few letters of anything — a scene, an effect, a session, a campaign, a combatant, a
/// command — and press Return. For the shortcuts you have not memorised.
struct CommandPalette: View {
    let items: [PaletteItem]
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private static let visibleLimit = 9

    private var results: [PaletteItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Array(items.prefix(Self.visibleLimit)) }

        return items
            .compactMap { item -> (PaletteItem, Int)? in
                guard let score = Self.score(needle, in: item.title.lowercased(),
                                             group: item.group.lowercased()) else { return nil }
                return (item, score)
            }
            // `sorted` is not stable, so the original position breaks ties.
            .enumerated()
            .sorted { a, b in
                a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset
            }
            .prefix(Self.visibleLimit)
            .map(\.element.0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Go to a scene, effect, note, campaign or command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit(runSelected)
                        // On the field itself: a focused text field gets the arrow keys first.
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.escape) { onDismiss(); return .handled }
                }
                .padding(12)

                Divider()

                if results.isEmpty {
                    Text("Nothing matches “\(query)”")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    row(item, selected: index == selection)
                                        .id(index)
                                        .onTapGesture { run(item) }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 380)
                        .onChange(of: selection) { _, new in proxy.scrollTo(new) }
                    }
                }
            }
            .frame(width: 540)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
            .shadow(radius: 24, y: 8)
            .padding(.top, 70)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .frame(width: 20)
                .foregroundStyle(selected ? Color.white : Color.secondary)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 8)
            Text(item.subtitle.isEmpty ? item.group : "\(item.group) · \(item.subtitle)")
                .font(.caption)
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(selected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func runSelected() {
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    private func run(_ item: PaletteItem) {
        onDismiss()
        // After the palette has gone, so a command that opens a sheet is not fighting it.
        DispatchQueue.main.async { item.run() }
    }

    /// Higher is better; nil is no match. A phrase found whole beats one whose letters merely
    /// appear in order, and an earlier or word-initial hit beats a later one.
    static func score(_ needle: String, in title: String, group: String) -> Int? {
        if let range = title.range(of: needle) {
            let offset = title.distance(from: title.startIndex, to: range.lowerBound)
            let atWordStart = offset == 0 || !title[title.index(title.startIndex, offsetBy: offset - 1)].isLetter
            return 1000 - offset * 4 + (atWordStart ? 200 : 0) - title.count
        }

        // Letters in order — "tvn" finds "Tavern".
        var remaining = needle[...]
        var gaps = 0
        var lastMatch = -1
        for (i, ch) in title.enumerated() where ch == remaining.first {
            if lastMatch >= 0 { gaps += i - lastMatch - 1 }
            lastMatch = i
            remaining.removeFirst()
            if remaining.isEmpty { return 300 - gaps * 3 - title.count }
        }

        // Last resort: the group word ("effect", "scene") plus the title.
        if group.contains(needle) { return 50 }
        return nil
    }
}
