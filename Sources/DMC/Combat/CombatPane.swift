import SwiftUI

/// Takes the browser's place in the centre pane. The web view is not torn down — it stays alive
/// inside its tab's controller — so swapping back finds D&D Beyond exactly where it was left.
struct CombatPane: View {
    @ObservedObject var combat: CombatTracker
    @Binding var railCollapsed: Bool
    @Binding var notesHidden: Bool
    @Binding var combatShown: Bool

    @State private var confirmingEnd = false
    /// Clearing confirms in place: the trash icon turns into a red button that disarms itself,
    /// so wiping the table is two deliberate clicks without a modal in the way.
    @State private var armedClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            CombatTable(combat: combat)
                .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("End this combat?", isPresented: $confirmingEnd) {
            Button("End Combat", role: .destructive) { combat.endCombat() }
        } message: {
            Text("Removes the NPCs and clears the party's initiative, ready for the next fight.")
        }
    }

    // Same height as the browser's bar, and text at the same size throughout, so swapping
    // between the two does not make the chrome jump.
    private var header: some View {
        HStack(spacing: 6) {
            Button { railCollapsed.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("\(railCollapsed ? "Expand" : "Collapse") the scene rail  ⌘⌥1")

            Divider().frame(height: 14)

            Button { combatShown = false } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text("Browser").font(.caption)
                }
            }
            .help("Back to D&D Beyond  ⌘⌥C")

            Divider().frame(height: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(combat.isRunning ? "Round \(combat.round)" : "Combat")
                    .font(.caption.weight(.semibold))
                if let current = combat.current {
                    Text("\(current.name)'s turn")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { combat.previous() } label: { Image(systemName: "backward.fill") }
                .disabled(!combat.isRunning)
                .help("Previous turn  ⌘⇧⏎")

            Button { combat.next() } label: {
                Label(combat.isRunning ? "Next Turn" : "Start Combat",
                      systemImage: combat.isRunning ? "forward.fill" : "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(combat.turnOrder.isEmpty)
            .help(combat.turnOrder.isEmpty ? "Enter at least one initiative"
                                           : "\(combat.isRunning ? "Next turn" : "Start combat")  ⌘⏎")

            Button { confirmingEnd = true } label: {
                Text("End Combat").font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .disabled(combat.combatants.isEmpty)
            .help("Remove the NPCs and clear the party's initiative")

            clearControl

            Divider().frame(height: 14)

            Button { notesHidden.toggle() } label: { Image(systemName: "sidebar.right") }
                .help("\(notesHidden ? "Show" : "Hide") notes  ⌘⌥2")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    @ViewBuilder private var clearControl: some View {
        if armedClear {
            Button {
                combat.clearAll()
                armedClear = false
            } label: {
                Text("Confirm clearing").font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            // Disarms itself, so a stray click earlier can't leave the table one click from
            // being wiped.
            .task {
                try? await Task.sleep(for: .seconds(4))
                armedClear = false
            }
        } else {
            Button { armedClear = true } label: { Image(systemName: "trash") }
                .disabled(combat.combatants.isEmpty)
                .help("Clear everyone, the party included")
        }
    }
}

/// Column widths shared by the heading, every row and the add row. They are constants rather
/// than something each part works out for itself, which is what keeps the three aligned — the
/// name column takes whatever is left.
private enum Col {
    static let type: CGFloat = 46
    static let number: CGFloat = 56
    static let end: CGFloat = 22
    static let spacing: CGFloat = 8
    static let inset: CGFloat = 10
}

/// One bordered table: a heading, the roster in initiative order, and — as its last row — the
/// place new combatants are entered. Column order is the same top to bottom:
/// type, name, HP, AC, initiative.
private struct CombatTable: View {
    @ObservedObject var combat: CombatTracker

    var body: some View {
        VStack(spacing: 0) {
            headings
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    // The add row follows the last combatant rather than being pinned to the
                    // bottom with a gap above it.
                    VStack(spacing: 0) {
                        if combat.combatants.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(combat.order.enumerated()), id: \.element.id) { index, combatant in
                                if index > 0 { Divider().opacity(0.5) }
                                CombatRow(combat: combat,
                                          combatant: combatant,
                                          isCurrent: combatant.id == combat.currentID)
                                    .id(combatant.id)
                            }
                        }

                        // Entering someone is a different act from editing the roster, so the
                        // add row sits in its own band rather than reading as one more combatant.
                        Divider()
                        Color(nsColor: .windowBackgroundColor).opacity(0.6).frame(height: 10)
                        Divider()
                        AddRow(combat: combat)
                    }
                }
                // Long fights outgrow the pane; follow the turn rather than make the DM scroll.
                .onChange(of: combat.currentID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }

    private var headings: some View {
        HStack(spacing: Col.spacing) {
            Text("Type").frame(width: Col.type)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("HP").frame(width: Col.number)
            Text("AC").frame(width: Col.number)
            Text("Init").frame(width: Col.number)
            Color.clear.frame(width: Col.end)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Col.inset)
        .frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.fencing")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No combatants yet")
                .font(.headline)
            Text("Add the party and the NPCs below, enter each initiative, then start combat.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: Row

private struct CombatRow: View {
    @ObservedObject var combat: CombatTracker
    let combatant: Combatant
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: Col.spacing) {
            TypeToggle(isPlayer: combatant.isPlayer) { isPlayer in
                combat.update(combatant.id) { $0.isPlayer = isPlayer }
            }
            .frame(width: Col.type)

            CommitField(value: combatant.name, prompt: "Name", numeric: false) { text in
                let clean = text.trimmingCharacters(in: .whitespaces)
                if !clean.isEmpty { combat.update(combatant.id) { $0.name = clean } }
            }
            .font(.body.weight(isCurrent ? .semibold : .regular))

            numberField(combatant.hp, help: "Hit points") { value in
                combat.update(combatant.id) { $0.hp = value }
            }
            numberField(combatant.armorClass, help: "Armor class") { value in
                combat.update(combatant.id) { $0.armorClass = value }
            }
            numberField(combatant.initiative, help: "Initiative. Leave empty until rolled.") { value in
                combat.update(combatant.id) { $0.initiative = value }
            }

            Button { combat.remove(combatant.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(width: Col.end)
                .help("Remove from combat")
        }
        .padding(.horizontal, Col.inset)
        .frame(height: 30)
        .background(isCurrent ? Color.accentColor.opacity(0.16) : Color.clear)
        // The turn marker is a bar on the table's edge rather than a column of its own, so the
        // columns stay exactly the ones in the heading.
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.accentColor).frame(width: 3).opacity(isCurrent ? 1 : 0)
        }
        .contextMenu {
            Button("Act Earlier (tied)") { combat.swapTie(combatant.id, direction: -1) }
                .disabled(!combat.canSwapTie(combatant.id, direction: -1))
            Button("Act Later (tied)") { combat.swapTie(combatant.id, direction: 1) }
                .disabled(!combat.canSwapTie(combatant.id, direction: 1))
            Divider()
            Button("Remove", role: .destructive) { combat.remove(combatant.id) }
        }
    }

    private func numberField(_ value: Int?, help: String,
                             commit: @escaping (Int?) -> Void) -> some View {
        CommitField(value: value.map(String.init) ?? "",
                    prompt: "—",
                    numeric: true,
                    alignment: .center) { commit(Int($0)) }
            .frame(width: Col.number)
            .help(help)
    }
}

/// Player character or NPC, with both choices always visible and the current one filled in —
/// a single icon that flips on click doesn't say what the other state is.
private struct TypeToggle: View {
    let isPlayer: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("person.fill", selected: isPlayer,
                    help: "Player character — kept when combat ends") { onChange(true) }
            segment("pawprint.fill", selected: !isPlayer,
                    help: "NPC — removed when combat ends") { onChange(false) }
        }
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func segment(_ symbol: String, selected: Bool, help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 23, height: 20)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.clear)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A text field that commits on Return or when it loses focus, not per keystroke.
///
/// This is what lets an initiative be typed into a live roster: committing "1" on the way to
/// "15" would re-sort the list mid-edit and carry the row out from under the cursor.
private struct CommitField: View {
    let value: String
    var prompt: String
    var numeric: Bool
    var alignment: TextAlignment = .leading
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .monospacedDigit()
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in if !focused { draft = new } }
            .onChange(of: draft) { _, new in
                // Digits and a leading minus only, so there is nothing to reject at commit.
                guard numeric else { return }
                let filtered = String(new.enumerated()
                    .filter { $0.element.isNumber || ($0.offset == 0 && $0.element == "-") }
                    .map(\.element))
                if filtered != new { draft = filtered }
            }
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onSubmit { commit() }
    }

    private func commit() {
        guard draft != value else { return }
        onCommit(draft.trimmingCharacters(in: .whitespaces))
        // A name emptied by mistake, or a lone "-", is rejected upstream; show what stuck.
        DispatchQueue.main.async { if !focused { draft = value } }
    }
}

// MARK: Add row

/// The table's last row, in the same columns as the rows above it. Return in any field adds.
/// The `×N` stepper sits inside the name column so no column has to widen to make room for it.
///
/// A name, an AC and an initiative are all required: a combatant without an initiative can't
/// take a turn, and one without an AC is a gap the DM would have to remember to fill. HP is
/// optional. Trying to add without them outlines what is missing instead of silently doing nothing.
private struct AddRow: View {
    @ObservedObject var combat: CombatTracker

    @State private var name = ""
    @State private var hp = ""
    @State private var armorClass = ""
    @State private var initiative = ""
    @State private var count = 1
    @State private var isPlayer = false
    @State private var showMissing = false
    @FocusState private var nameFocused: Bool

    private var nameOK: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var acOK: Bool { Int(armorClass) != nil }
    private var initiativeOK: Bool { Int(initiative) != nil }
    private var canAdd: Bool { nameOK && acOK && initiativeOK }

    var body: some View {
        HStack(spacing: Col.spacing) {
            TypeToggle(isPlayer: isPlayer) { isPlayer = $0 }
                .frame(width: Col.type)

            HStack(spacing: 6) {
                TextField("Add combatant", text: $name)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(add)
                Stepper(value: $count, in: 1...30) {
                    Text("×\(count)").font(.caption).monospacedDigit()
                }
                .controlSize(.small)
                .fixedSize()
                .help("How many to add. A group is numbered and shares its HP, AC and initiative.")
            }
            .padding(.horizontal, 4)
            .modifier(MissingOutline(show: showMissing && !nameOK))

            numberField("HP", text: $hp, missing: false)
            numberField("AC", text: $armorClass, missing: showMissing && !acOK)
            numberField("Init", text: $initiative, missing: showMissing && !initiativeOK)

            Button(action: add) { Image(systemName: "plus.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(canAdd ? Color.accentColor : .secondary)
                .frame(width: Col.end)
                .help(canAdd ? "Add to combat  ⏎" : "A name, AC and initiative are needed")
        }
        .padding(.horizontal, Col.inset)
        .frame(height: 38)
        .onChange(of: name) { _, _ in showMissing = false }
    }

    private func numberField(_ prompt: String, text: Binding<String>, missing: Bool) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .padding(.horizontal, 4)
            .frame(width: Col.number)
            .modifier(MissingOutline(show: missing))
            .onChange(of: text.wrappedValue) { _, new in
                showMissing = false
                let filtered = String(new.enumerated()
                    .filter { $0.element.isNumber || ($0.offset == 0 && $0.element == "-") }
                    .map(\.element))
                if filtered != new { text.wrappedValue = filtered }
            }
            .onSubmit(add)
    }

    private func add() {
        guard canAdd else {
            showMissing = true
            return
        }
        combat.add(name: name,
                   initiative: Int(initiative),
                   armorClass: Int(armorClass),
                   hp: Int(hp),
                   isPlayer: isPlayer,
                   count: count)
        // The type stays: the party tends to be entered in one go.
        name = ""
        hp = ""
        armorClass = ""
        initiative = ""
        count = 1
        showMissing = false
        nameFocused = true
    }
}

private struct MissingOutline: ViewModifier {
    let show: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red, lineWidth: 1).opacity(show ? 1 : 0))
    }
}
