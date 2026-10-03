import SwiftUI

/// Takes the browser's place in the centre pane. The web view is not torn down — it stays alive
/// inside its tab's controller — so swapping back finds D&D Beyond exactly where it was left.
///
/// This is for tables that run combat on paper or in their heads rather than in a VTT.
struct CombatPane: View {
    var combat: CombatTracker
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
            Text("Removes the NPCs and clears the party's initiative and conditions, ready for the next fight. Undo brings it back.")
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

            Button { combat.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!combat.canUndo)
                .help("Undo the last change  ⌘⌥Z")

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

            moreMenu

            clearControl

            Divider().frame(height: 14)

            Button { notesHidden.toggle() } label: { Image(systemName: "sidebar.right") }
                .help("\(notesHidden ? "Show" : "Hide") notes  ⌘⌥2")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var moreMenu: some View {
        Menu {
            Button("Roll Initiative for NPCs", systemImage: "dice") { combat.rollNPCInitiative() }
                .disabled(!combat.hasUnrolledNPCs)
            Button("Add Lair Actions (initiative 20)", systemImage: "building.columns") {
                combat.addLair()
            }
            .disabled(combat.hasLair)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Roll NPC initiative, add lair actions")
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
    static let hp: CGFloat = 88
    static let number: CGFloat = 48
    static let initiative: CGFloat = 66
    static let end: CGFloat = 22
    static let spacing: CGFloat = 8
    static let inset: CGFloat = 10
    /// The height of a row's first line. Every cell is this tall and the row is top-aligned, so
    /// when conditions or death saves add a second line under the name, nothing else moves.
    static let line: CGFloat = 22
}

/// Keeps digits, and one leading sign where a sign means something (a negative initiative bonus,
/// "-7" damage). The Unicode minus some keyboards produce is turned into a plain one.
private func digitsOnly(_ text: String, signed: Bool) -> String {
    String(text.enumerated().compactMap { offset, ch -> Character? in
        if ch.isASCII && ch.isNumber { return ch }
        if signed && offset == 0 {
            if ch == "-" || ch == "−" { return "-" }
            if ch == "+" { return "+" }
        }
        return nil
    })
}

/// One bordered table: a heading, the roster in initiative order, and — as its last row — the
/// place new combatants are entered. Column order is the same top to bottom:
/// type, name, HP, AC, mod, initiative.
private struct CombatTable: View {
    var combat: CombatTracker

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
            Text("HP").frame(width: Col.hp)
            Text("AC").frame(width: Col.number)
            Text("Mod").frame(width: Col.number)
                .help("Initiative bonus, added to the d20 when the app rolls")
            Text("Init").frame(width: Col.initiative)
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
            Text("Add the party and the NPCs below — look a monster up, or type its numbers — then roll or enter initiative and start combat.")
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
    var combat: CombatTracker
    let combatant: Combatant
    let isCurrent: Bool

    @State private var showConditions = false

    private var showsDeathSaves: Bool { combatant.isPlayer && combatant.isDown }

    var body: some View {
        HStack(alignment: .top, spacing: Col.spacing) {
            leading.frame(width: Col.type, height: Col.line)

            VStack(alignment: .leading, spacing: 4) {
                nameLine.frame(height: Col.line)
                if !combatant.conditions.isEmpty || showsDeathSaves { detailLine }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if combatant.isLair {
                Text("—").foregroundStyle(.tertiary).frame(width: Col.hp, height: Col.line)
                Text("—").foregroundStyle(.tertiary).frame(width: Col.number, height: Col.line)
                Text("—").foregroundStyle(.tertiary).frame(width: Col.number, height: Col.line)
            } else {
                HPField(hp: combatant.hp, maxHP: combatant.maxHP,
                        bloodied: combatant.isBloodied, down: combatant.isDown) { text in
                    combat.enterHP(combatant.id, text)
                }
                .frame(width: Col.hp, height: Col.line)

                numberField(combatant.armorClass, help: "Armor class") { value in
                    combat.update(combatant.id) { $0.armorClass = value }
                }
                .frame(width: Col.number, height: Col.line)

                numberField(combatant.initiativeBonus, help: "Initiative bonus — Dexterity modifier",
                            signed: true) { value in
                    combat.update(combatant.id) { $0.initiativeBonus = value }
                }
                .frame(width: Col.number, height: Col.line)
            }

            initiativeCell.frame(width: Col.initiative, height: Col.line)

            Button { combat.remove(combatant.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(width: Col.end, height: Col.line)
                .help("Remove from combat  (Undo brings it back)")
        }
        .padding(.horizontal, Col.inset)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(isCurrent ? Color.accentColor.opacity(0.16) : Color.clear)
        // The turn marker is a bar on the table's edge rather than a column of its own, so the
        // columns stay exactly the ones in the heading.
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.accentColor).frame(width: 3).opacity(isCurrent ? 1 : 0)
        }
        .contextMenu {
            if !combatant.isLair {
                Button("Roll Initiative", systemImage: "dice") { combat.rollInitiative(combatant.id) }
                Button("Add Condition…", systemImage: "tag") { showConditions = true }
                Divider()
            }
            Button("Act Earlier (tied)") { combat.swapTie(combatant.id, direction: -1) }
                .disabled(!combat.canSwapTie(combatant.id, direction: -1))
            Button("Act Later (tied)") { combat.swapTie(combatant.id, direction: 1) }
                .disabled(!combat.canSwapTie(combatant.id, direction: 1))
            Divider()
            Button("Remove", role: .destructive) { combat.remove(combatant.id) }
        }
    }

    @ViewBuilder private var leading: some View {
        if combatant.isLair {
            Image(systemName: "building.columns")
                .foregroundStyle(.secondary)
                .help("Lair actions act on initiative 20, losing ties")
        } else {
            TypeToggle(isPlayer: combatant.isPlayer) { isPlayer in
                combat.update(combatant.id) { $0.isPlayer = isPlayer }
            }
        }
    }

    private var nameLine: some View {
        HStack(spacing: 6) {
            CommitField(value: combatant.name, prompt: "Name", kind: .text) { text in
                let clean = text.trimmingCharacters(in: .whitespaces)
                if !clean.isEmpty { combat.update(combatant.id) { $0.name = clean } }
            }
            .font(.body.weight(isCurrent ? .semibold : .regular))
            .strikethrough(combatant.isDown && !combatant.isPlayer || combatant.isDead)
            .foregroundStyle(combatant.isDown && !combatant.isPlayer ? .secondary : .primary)

            if combatant.isDead {
                badge("dead", .red)
            } else if combatant.isDown {
                badge(combatant.isStable ? "stable" : "down",
                      combatant.isStable ? .green : .red)
            }

            if !combatant.isLair {
                Button { showConditions = true } label: { Image(systemName: "tag") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(combatant.conditions.isEmpty ? .tertiary : .secondary)
                    .help("Add a condition")
                    .popover(isPresented: $showConditions, arrowEdge: .bottom) {
                        ConditionPicker(name: combatant.name) { name, rounds in
                            combat.addCondition(combatant.id, name: name, rounds: rounds)
                        }
                    }
            }
        }
    }

    private var detailLine: some View {
        FlowLayout(spacing: 4, lineSpacing: 3) {
            ForEach(combatant.conditions) { condition in
                ConditionChip(condition: condition) {
                    combat.removeCondition(combatant.id, conditionID: condition.id)
                }
            }
            if showsDeathSaves && !combatant.isDead {
                DeathSaves(successes: combatant.deathSuccesses,
                           failures: combatant.deathFailures) { s, f in
                    combat.setDeathSaves(combatant.id, successes: s, failures: f)
                }
            }
        }
    }

    private var initiativeCell: some View {
        HStack(spacing: 2) {
            CommitField(value: combatant.initiative.map(String.init) ?? "",
                        prompt: "—", kind: .signed, alignment: .center) { text in
                combat.update(combatant.id) { $0.initiative = Int(text) }
            }
            .help("Initiative. Leave empty until rolled.")

            if combatant.initiative == nil && !combatant.isLair {
                Button { combat.rollInitiative(combatant.id) } label: { Image(systemName: "dice") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Roll d20 + the Mod")
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func numberField(_ value: Int?, help: String, signed: Bool = false,
                             commit: @escaping (Int?) -> Void) -> some View {
        CommitField(value: value.map(String.init) ?? "",
                    prompt: "—",
                    kind: signed ? .signed : .number,
                    alignment: .center) { commit(Int($0)) }
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

// MARK: Fields

/// What a field accepts.
private enum FieldKind {
    case text, number
    /// Digits with an optional leading + or −: an initiative bonus, or a negative initiative.
    case signed
}

/// A text field that commits on Return or when it loses focus, not per keystroke.
///
/// This is what lets an initiative be typed into a live roster: committing "1" on the way to
/// "15" would re-sort the list mid-edit and carry the row out from under the cursor.
private struct CommitField: View {
    let value: String
    var prompt: String
    var kind: FieldKind
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
                // Digits only, so there is nothing to reject at commit.
                guard kind != .text else { return }
                let filtered = digitsOnly(new, signed: kind == .signed)
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

/// Current HP, with the maximum beside it. Clicking in clears the box and shows the current
/// number faintly: type a new total ("23"), or just the change ("-7" for damage, "+5" for
/// healing), and press Return. Leaving it empty changes nothing.
private struct HPField: View {
    let hp: Int?
    let maxHP: Int?
    let bloodied: Bool
    let down: Bool
    let onEnter: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var tint: Color {
        down ? .red : (bloodied ? .orange : .primary)
    }

    var body: some View {
        HStack(spacing: 2) {
            ZStack {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .focused($focused)
                    .onChange(of: draft) { _, new in
                        let filtered = digitsOnly(new, signed: true)
                        if filtered != new { draft = filtered }
                    }
                    .onChange(of: focused) { _, now in if !now { commit() } }
                    .onSubmit { commit() }

                // The shown value is an overlay, so a field being typed into is not fighting a
                // number that is already in it.
                if draft.isEmpty {
                    Text(hp.map(String.init) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(hp == nil ? Color.secondary : tint)
                        .opacity(focused ? 0.35 : 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 44)
            .help("Type a total, or −7 for damage, +5 for healing")

            Text(maxHP.map { "/\($0)" } ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private func commit() {
        let text = draft
        draft = ""
        if !text.isEmpty { onEnter(text) }
    }
}

// MARK: Conditions and death saves

private struct ConditionChip: View {
    let condition: Condition
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(condition.name)
            if let rounds = condition.rounds {
                Text("· \(rounds)").foregroundStyle(.secondary).monospacedDigit()
            }
            Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 7, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.18))
        .clipShape(Capsule())
        .help(condition.rounds.map { "\($0) turn\($0 == 1 ? "" : "s") left — counts down as this creature's turn ends" }
              ?? "Until removed")
    }
}

private struct ConditionPicker: View {
    let name: String
    let onApply: (String, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var timed = false
    @State private var rounds = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Condition on \(name)").font(.headline)

            Toggle(isOn: $timed) {
                HStack(spacing: 6) {
                    Text("Ends after")
                    Stepper(value: $rounds, in: 1...99) {
                        Text("\(rounds) turn\(rounds == 1 ? "" : "s")").monospacedDigit()
                    }
                    .disabled(!timed)
                    .fixedSize()
                }
            }
            .help("Counts down as this creature's own turn ends, and drops off at zero")

            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(Condition.common, id: \.self) { condition in
                    Button(condition) { apply(condition) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack {
                TextField("Something else…", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { apply(custom) }
                Button("Add") { apply(custom) }
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private func apply(_ condition: String) {
        onApply(condition, timed ? rounds : nil)
        dismiss()
    }
}

/// Three successes and three failures, filled left to right by clicking. Clicking the last filled
/// circle empties it again.
private struct DeathSaves: View {
    let successes: Int
    let failures: Int
    let onChange: (Int, Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if successes >= 3 {
                Text("stable").font(.caption2).foregroundStyle(.green)
            }
            HStack(spacing: 2) {
                Image(systemName: "checkmark").font(.system(size: 8)).foregroundStyle(.green)
                ForEach(0..<3, id: \.self) { i in
                    pip(filled: i < successes, color: .green) {
                        onChange(successes == i + 1 ? i : i + 1, failures)
                    }
                }
            }
            HStack(spacing: 2) {
                Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(.red)
                ForEach(0..<3, id: \.self) { i in
                    pip(filled: i < failures, color: .red) {
                        onChange(successes, failures == i + 1 ? i : i + 1)
                    }
                }
            }
        }
        .help("Death saving throws")
    }

    private func pip(filled: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(filled ? color : Color.clear)
                .overlay(Circle().stroke(color.opacity(0.7), lineWidth: 1))
                .frame(width: 10, height: 10)
        }
        .buttonStyle(.plain)
    }
}

/// Lays children out left to right, wrapping onto new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: Add row

/// The table's last row, in the same columns as the rows above it. Return in any field adds.
/// The `×N` stepper sits inside the name column so no column has to widen to make room for it.
///
/// A name, an AC and an initiative are required: a combatant without an initiative can't take a
/// turn, and one without an AC is a gap the DM would have to remember to fill. HP and the
/// initiative bonus are optional. The one exception is a group that rolls separately: it needs
/// no initiative typed, because each member gets its own roll. Trying to add without what is
/// required outlines what is missing instead of silently doing nothing.
private struct AddRow: View {
    var combat: CombatTracker

    @State private var name = ""
    @State private var hp = ""
    @State private var armorClass = ""
    @State private var bonus = ""
    @State private var initiative = ""
    @State private var count = 1
    @State private var isPlayer = false
    @State private var sharedInitiative = true
    @State private var showMissing = false
    @State private var showMonsters = false
    @FocusState private var nameFocused: Bool

    private var nameOK: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var acOK: Bool { Int(armorClass) != nil }
    private var rollsEach: Bool { count > 1 && !sharedInitiative }
    private var initiativeOK: Bool { rollsEach || Int(initiative) != nil }
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

                Button { showMonsters = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Look up a monster — fills in name, HP, AC and initiative bonus")
                    .popover(isPresented: $showMonsters, arrowEdge: .bottom) {
                        MonsterSearch(initialQuery: name) { monster in fill(from: monster) }
                    }

                if count > 1 {
                    Button { sharedInitiative.toggle() } label: {
                        Image(systemName: sharedInitiative ? "person.3.fill" : "person.3")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(sharedInitiative ? Color.accentColor : .secondary)
                    .help(sharedInitiative
                          ? "The group shares one initiative. Click for each to roll its own."
                          : "Each rolls its own d20 + Mod when added. Click for one shared initiative.")
                }

                Stepper(value: $count, in: 1...30) {
                    Text("×\(count)").font(.caption).monospacedDigit()
                }
                .controlSize(.small)
                .fixedSize()
                .help("How many to add. A group is numbered and shares its HP and AC.")
            }
            .padding(.horizontal, 4)
            .modifier(MissingOutline(show: showMissing && !nameOK))

            numberField("HP", text: $hp, missing: false)
                .frame(width: Col.hp)
            numberField("AC", text: $armorClass, missing: showMissing && !acOK)
                .frame(width: Col.number)
            numberField("Mod", text: $bonus, missing: false, signed: true)
                .frame(width: Col.number)

            HStack(spacing: 2) {
                numberField(rollsEach ? "roll" : "Init", text: $initiative,
                            missing: showMissing && !initiativeOK, signed: true)
                    .disabled(rollsEach)
                Button {
                    initiative = String(CombatTracker.rollD20(bonus: Int(bonus)))
                } label: { Image(systemName: "dice") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(rollsEach)
                    .help("Roll d20 + the Mod")
            }
            .frame(width: Col.initiative)

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

    private func numberField(_ prompt: String, text: Binding<String>, missing: Bool,
                             signed: Bool = false) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .padding(.horizontal, 4)
            .modifier(MissingOutline(show: missing))
            .onChange(of: text.wrappedValue) { _, new in
                showMissing = false
                let filtered = digitsOnly(new, signed: signed)
                if filtered != new { text.wrappedValue = filtered }
            }
            .onSubmit(add)
    }

    private func fill(from monster: Open5eMonster) {
        name = monster.name
        hp = monster.hitPoints.map(String.init) ?? ""
        armorClass = monster.armorClass.map(String.init) ?? ""
        bonus = monster.initiativeBonus.map { String($0) } ?? ""
        isPlayer = false
        showMonsters = false
        nameFocused = true
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
                   count: count,
                   initiativeBonus: Int(bonus),
                   groupInitiative: sharedInitiative)
        // The type stays: the party tends to be entered in one go.
        name = ""
        hp = ""
        armorClass = ""
        bonus = ""
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

// MARK: Monster lookup

/// Searches Open5e as you type and hands back the chosen monster.
private struct MonsterSearch: View {
    let onPick: (Open5eMonster) -> Void

    @State private var query: String
    @State private var results: [Open5eMonster] = []
    @State private var searching = false
    @State private var failure: String?
    @FocusState private var focused: Bool

    init(initialQuery: String, onPick: @escaping (Open5eMonster) -> Void) {
        self.onPick = onPick
        _query = State(initialValue: initialQuery.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search monsters — goblin, owlbear…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if let first = results.first { onPick(first) } }
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            if let failure {
                Label(failure, systemImage: "wifi.slash")
                    .font(.caption).foregroundStyle(.secondary)
            } else if results.isEmpty {
                Text(query.trimmingCharacters(in: .whitespaces).count < 2
                     ? "Type at least two letters. Results come from Open5e — the SRD first."
                     : (searching ? "" : "No monsters match."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { monster in
                            Button { onPick(monster) } label: { row(monster) }
                                .buttonStyle(.plain)
                            Divider().opacity(0.5)
                        }
                    }
                }
                .frame(height: 260)
            }
        }
        .padding(10)
        .frame(width: 380)
        .onAppear { focused = true }
        // Restarted on every keystroke, and cancelled when the next arrives, so only the text the
        // DM stopped on is ever sent.
        .task(id: query) { await search() }
    }

    private func row(_ monster: Open5eMonster) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(monster.name).font(.callout)
                Text([monster.summary, monster.source ?? ""].filter { !$0.isEmpty }
                        .joined(separator: " — "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 8) {
                stat("HP", monster.hitPoints)
                stat("AC", monster.armorClass)
            }
            .font(.caption.monospacedDigit())
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.tertiary)
            Text(value.map(String.init) ?? "—")
        }
    }

    private func search() async {
        failure = nil
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await Open5eClient.search(query)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            Log.network.error("open5e: \(error.localizedDescription, privacy: .public)")
            results = []
            failure = "Couldn't reach Open5e. Check your connection."
        }
    }
}
