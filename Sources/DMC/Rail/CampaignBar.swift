import SwiftUI

/// Campaign switcher for the rail header. Collapses to a single icon along with the rail.
struct CampaignMenu: View {
    @ObservedObject var campaigns: CampaignStore
    @ObservedObject var router: UIRouter
    let collapsed: Bool

    var body: some View {
        Menu {
            Section("Switch to") {
                ForEach(campaigns.sorted) { campaign in
                    Button {
                        campaigns.activate(campaign.id)
                    } label: {
                        if campaign.id == campaigns.activeID {
                            Label(campaign.name, systemImage: "checkmark")
                        } else {
                            Text(campaign.name)
                        }
                    }
                }
            }
            Divider()
            Button("New Campaign…") { router.showNewCampaign = true }
            if let active = campaigns.active {
                Button("Rename “\(active.name)”…") { router.renaming = active }
                Button("Delete “\(active.name)”…", role: .destructive) {
                    router.deleting = active
                }
                .disabled(campaigns.campaigns.count < 2)
            }
        } label: {
            if collapsed {
                Image(systemName: "books.vertical")
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "books.vertical").font(.caption)
                    Text(campaigns.active?.name ?? "Campaign")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(campaigns.active.map { "Campaign: \($0.name)" } ?? "Campaign")
    }
}

/// Shared by the new and rename flows — the only difference is the title and what Save does.
struct CampaignNameSheet: View {
    let title: String
    let confirmLabel: String
    @State var name: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Campaign name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            Text("Scenes, notes, tabs and macropad bindings are kept per campaign. "
                 + "Your audio library is shared, so nothing is re-downloaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(confirmLabel) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}

struct DeleteCampaignSheet: View {
    let campaign: Campaign
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Delete “\(campaign.name)”?", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("This removes that campaign's scenes, notes, tabs and macropad bindings. "
                 + "Your audio library is shared and stays untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Delete", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
