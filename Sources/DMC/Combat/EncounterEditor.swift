import SwiftUI

/// Where a session's fights are prepared ahead of time: which monsters are in each, and which
/// sound scene plays when it starts. Changes are saved as they are made.
struct EncounterEditor: View {
    var combat: CombatTracker
    var scenes: SceneStore
    /// Puts the encounter on the table. The pane decides whether that needs confirming.
    let onLoad: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    private var selected: Encounter? { combat.encounters.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                list.frame(minWidth: 180, idealWidth: 200, maxWidth: 260)
                detail.frame(minWidth: 420)
            }
            Divider()
            HStack {
                Text("The party is shared by every encounter and keeps its HP between them.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 700, height: 500)
        .onAppear { selection = combat.activeEncounterID ?? combat.encounters.first?.id }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(combat.encounters) { encounter in
                    HStack(spacing: 6) {
                        Image(systemName: encounter.id == combat.activeEncounterID ? "play.circle.fill"
                              : (encounter.done ? "checkmark.circle" : "circle"))
                            .foregroundStyle(encounter.id == combat.activeEncounterID ? Color.accentColor
                                             : .secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(encounter.name).lineLimit(1)
                            Text("\(encounter.headcount) monster\(encounter.headcount == 1 ? "" : "s")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let scene = scenes.scenes.first(where: { $0.id == encounter.sceneID }) {
                            Image(systemName: scene.symbol).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(encounter.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 2) {
                Button {
                    selection = combat.addEncounter(name: "")
                } label: { Image(systemName: "plus") }
                    .help("New encounter")
                Button {
                    guard let id = selection else { return }
                    let next = combat.encounters.firstIndex { $0.id == id }
                        .flatMap { i in combat.encounters.indices.contains(i + 1) ? combat.encounters[i + 1].id
                                        : (i > 0 ? combat.encounters[i - 1].id : nil) }
                    combat.removeEncounter(id)
                    selection = next
                } label: { Image(systemName: "minus") }
                    .disabled(selected == nil)
                    .help("Delete the selected encounter")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let encounter = selected {
            EncounterDetail(combat: combat, scenes: scenes, encounter: encounter, onLoad: onLoad)
                .id(encounter.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 32)).foregroundStyle(.tertiary)
                Text("No encounters yet").font(.headline)
                Text("Prepare a fight — its monsters and the scene that plays — and load it onto the table when the party gets there.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("New Encounter") { selection = combat.addEncounter(name: "") }
                    .padding(.top, 4)
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum EncounterCol {
    static let count: CGFloat = 78
    static let number: CGFloat = 48
    static let end: CGFloat = 22
    static let spacing: CGFloat = 8
}

private struct EncounterDetail: View {
    var combat: CombatTracker
    var scenes: SceneStore
    let encounter: Encounter
    let onLoad: (UUID) -> Void

    private var sceneMissing: Bool {
        encounter.sceneID != nil && !scenes.contains(encounter.sceneID!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CommitField(value: encounter.name, prompt: "Encounter name", kind: .text) { text in
                    let clean = text.trimmingCharacters(in: .whitespaces)
                    if !clean.isEmpty { combat.updateEncounter(encounter.id) { $0.name = clean } }
                }
                .font(.title3.weight(.semibold))

                Button {
                    onLoad(encounter.id)
                } label: {
                    Label("Load onto table", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                .help("Replace the NPCs on the table with this encounter's monsters")
            }

            HStack {
                Text("Scene").foregroundStyle(.secondary)
                Picker("Scene", selection: sceneBinding) {
                    Text("None").tag(UUID?.none)
                    if sceneMissing { Text("(deleted scene)").tag(encounter.sceneID) }
                    ForEach(scenes.scenes) { scene in
                        Label(scene.name, systemImage: scene.symbol).tag(UUID?.some(scene.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Text("plays when combat starts")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            monsters
        }
        .padding(14)
    }

    private var sceneBinding: Binding<UUID?> {
        Binding(get: { encounter.sceneID },
                set: { id in combat.updateEncounter(encounter.id) { $0.sceneID = id } })
    }

    private var monsters: some View {
        VStack(spacing: 0) {
            HStack(spacing: EncounterCol.spacing) {
                Text("Monster").frame(maxWidth: .infinity, alignment: .leading)
                Text("Count").frame(width: EncounterCol.count)
                Text("HP").frame(width: EncounterCol.number)
                Text("AC").frame(width: EncounterCol.number)
                Text("Mod").frame(width: EncounterCol.number)
                Color.clear.frame(width: EncounterCol.end)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(encounter.monsters) { monster in
                        MonsterRow(combat: combat, encounterID: encounter.id, monster: monster)
                        Divider().opacity(0.5)
                    }
                    if encounter.monsters.isEmpty {
                        Text("No monsters yet — add them below.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(16).frame(maxWidth: .infinity)
                    }
                }
            }

            Divider()
            AddMonsterRow(combat: combat, encounterID: encounter.id)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }
}

private struct MonsterRow: View {
    var combat: CombatTracker
    let encounterID: UUID
    let monster: PlannedMonster

    var body: some View {
        HStack(spacing: EncounterCol.spacing) {
            CommitField(value: monster.name, prompt: "Name", kind: .text) { text in
                let clean = text.trimmingCharacters(in: .whitespaces)
                if !clean.isEmpty { edit { $0.name = clean } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Stepper(value: Binding(get: { monster.count }, set: { n in edit { $0.count = n } }),
                    in: 1...30) {
                Text("×\(monster.count)").font(.caption).monospacedDigit()
            }
            .controlSize(.small)
            .frame(width: EncounterCol.count)

            number(monster.hp, help: "Hit points each") { v in edit { $0.hp = v } }
            number(monster.armorClass, help: "Armor class") { v in edit { $0.armorClass = v } }
            number(monster.initiativeBonus, help: "Initiative bonus", signed: true) { v in
                edit { $0.initiativeBonus = v }
            }

            Button {
                combat.updateEncounter(encounterID) { e in e.monsters.removeAll { $0.id == monster.id } }
            } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(width: EncounterCol.end)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private func edit(_ change: @escaping (inout PlannedMonster) -> Void) {
        combat.updateEncounter(encounterID) { e in
            if let i = e.monsters.firstIndex(where: { $0.id == monster.id }) { change(&e.monsters[i]) }
        }
    }

    private func number(_ value: Int?, help: String, signed: Bool = false,
                        commit: @escaping (Int?) -> Void) -> some View {
        CommitField(value: value.map(String.init) ?? "", prompt: "—",
                    kind: signed ? .signed : .number, alignment: .center) { commit(Int($0)) }
            .help(help)
            .frame(width: EncounterCol.number)
    }
}

private struct AddMonsterRow: View {
    var combat: CombatTracker
    let encounterID: UUID

    @State private var name = ""
    @State private var count = 1
    @State private var hp = ""
    @State private var armorClass = ""
    @State private var bonus = ""
    @State private var showMonsters = false
    @FocusState private var nameFocused: Bool

    private var canAdd: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: EncounterCol.spacing) {
            HStack(spacing: 6) {
                TextField("Add monster", text: $name)
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
            }
            .frame(maxWidth: .infinity)

            Stepper(value: $count, in: 1...30) {
                Text("×\(count)").font(.caption).monospacedDigit()
            }
            .controlSize(.small)
            .frame(width: EncounterCol.count)

            field("HP", $hp)
            field("AC", $armorClass)
            field("Mod", $bonus, signed: true)

            Button(action: add) { Image(systemName: "plus.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(canAdd ? Color.accentColor : .secondary)
                .frame(width: EncounterCol.end)
                .disabled(!canAdd)
                .help("Add to the encounter  ⏎")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
    }

    private func field(_ prompt: String, _ text: Binding<String>, signed: Bool = false) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: EncounterCol.number)
            .onChange(of: text.wrappedValue) { _, new in
                let filtered = digitsOnly(new, signed: signed)
                if filtered != new { text.wrappedValue = filtered }
            }
            .onSubmit(add)
    }

    private func fill(from monster: Open5eMonster) {
        name = monster.name
        hp = monster.hitPoints.map(String.init) ?? ""
        armorClass = monster.armorClass.map(String.init) ?? ""
        bonus = monster.initiativeBonus.map(String.init) ?? ""
        showMonsters = false
        nameFocused = true
    }

    private func add() {
        guard canAdd else { return }
        let planned = PlannedMonster(name: name.trimmingCharacters(in: .whitespaces),
                                     count: count, armorClass: Int(armorClass), hp: Int(hp),
                                     initiativeBonus: Int(bonus))
        combat.updateEncounter(encounterID) { $0.monsters.append(planned) }
        name = ""; hp = ""; armorClass = ""; bonus = ""; count = 1
        nameFocused = true
    }
}
