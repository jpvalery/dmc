import SwiftUI

/// Browse and download the Tabletop Audio ambience catalogue into the vault.
struct TabletopBrowser: View {
    @ObservedObject var catalogue: TabletopCatalogue
    @ObservedObject var downloader: TrackDownloader

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var genre: String?
    @State private var downloadedOnly = false
    @State private var selection: Set<Int> = []
    @State private var collection: TabletopCatalogue.Collection?
    @State private var collectionSize = 12

    /// Roughly 14 MB per 10-minute track, so a set can be sized before committing to it.
    private static let megabytesPerTrack = 14

    private var matches: [TTATrack] {
        if let collection {
            let picked = catalogue.tracks(in: collection, limit: collectionSize)
            guard downloadedOnly else { return picked }
            return picked.filter(\.isDownloaded)
        }
        return catalogue.filtered(search: search, genre: genre, downloadedOnly: downloadedOnly)
    }

    private var notYetDownloaded: [TTATrack] { matches.filter { !$0.isDownloaded } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 580)
        .task { if catalogue.tracks.isEmpty { await catalogue.refresh() } }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tabletop Audio").font(.headline)
                if catalogue.isLoading { ProgressView().controlSize(.small) }
                Spacer()
                Button { Task { await catalogue.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh the catalogue")
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 8) {
                TextField("Search titles, tags and descriptions", text: $search)
                    .textFieldStyle(.roundedBorder)

                Picker("", selection: $genre) {
                    Text("All genres").tag(String?.none)
                    ForEach(catalogue.allGenres, id: \.self) { g in
                        Text(g.capitalized).tag(String?.some(g))
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Toggle("In vault", isOn: $downloadedOnly).toggleStyle(.checkbox)
            }

            collectionChips

            if let error = catalogue.loadError {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }

    private var collectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TabletopCatalogue.collections) { item in
                    let isOn = collection == item
                    Button {
                        collection = isOn ? nil : item
                        if !isOn { search = ""; genre = nil }
                        selection = []
                    } label: {
                        Label(item.name, systemImage: item.symbol)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isOn ? Color.accentColor.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if collection != nil {
                    Divider().frame(height: 14)
                    Stepper("Top \(collectionSize)", value: $collectionSize, in: 4...40, step: 4)
                        .font(.caption)
                        .fixedSize()
                }
            }
        }
    }

    private var content: some View {
        Group {
            if catalogue.tracks.isEmpty && !catalogue.isLoading {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "icloud.slash").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Catalogue not loaded").font(.callout).foregroundStyle(.secondary)
                    Button("Try again") { Task { await catalogue.refresh() } }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(matches, selection: $selection) { track in
                    TrackRow(track: track, downloader: downloader)
                        .tag(track.key)
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if downloader.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Downloading \(downloader.completed + 1) of \(downloader.totalInBatch)…")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Cancel queue") { downloader.cancelPending() }
                        .buttonStyle(.link).font(.caption)
                } else {
                    Text("\(matches.count) track\(matches.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !notYetDownloaded.isEmpty {
                    Button("Download all \(notYetDownloaded.count) (~\(notYetDownloaded.count * Self.megabytesPerTrack) MB)") {
                        downloader.enqueue(notYetDownloaded)
                        selection = []
                    }
                }
                Button("Download selected (\(selection.count))") {
                    downloader.enqueue(matches.filter { selection.contains($0.key) })
                    selection = []
                }
                .disabled(selection.isEmpty)
            }

            Text("10-minute ambiences from tabletopaudio.com, licensed CC BY-NC-ND 4.0. "
                 + "Credit is written to ATTRIBUTION.md alongside the audio.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

private struct TrackRow: View {
    let track: TTATrack
    @ObservedObject var downloader: TrackDownloader

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.title).font(.callout.weight(.medium))
                    Text(track.type).font(.caption2).foregroundStyle(.tertiary)
                }
                if !track.flavor.isEmpty {
                    Text(track.flavor).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !track.tags.isEmpty {
                    Text(track.tags.prefix(8).joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            if track.isDownloaded {
                Label("In vault", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .help("Already in the vault")
            } else if downloader.active?.key == track.key {
                ProgressView().controlSize(.small)
            } else if let failure = downloader.failures[track.key] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(failure)
            } else {
                Button {
                    downloader.enqueue([track])
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .help("Download to the vault")
            }
        }
        .padding(.vertical, 3)
    }
}
