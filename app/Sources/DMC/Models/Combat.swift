import Foundation
import Observation

/// A condition on a combatant — "Stunned", "Concentrating" — optionally counting down.
struct Condition: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Turns of the afflicted combatant left. It drops by one at the *end* of their own turn and
    /// the condition goes when it reaches zero — "until the end of its next turn" is a 1.
    /// `nil` lasts until removed by hand.
    var rounds: Int?

    init(name: String, rounds: Int? = nil) {
        self.name = name
        self.rounds = rounds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Condition"
        rounds = try c.decodeIfPresent(Int.self, forKey: .rounds)
    }

    /// The SRD conditions, plus a few a DM tracks as often as any of them.
    static let common = ["Blinded", "Charmed", "Concentrating", "Deafened", "Frightened", "Grappled",
                         "Incapacitated", "Invisible", "Paralyzed", "Petrified", "Poisoned", "Prone",
                         "Restrained", "Stunned", "Unconscious", "Hasted", "Blessed"]

    /// The SF Symbol for a condition, by name. The SRD ones are matched exactly, and a custom name
    /// is matched on a keyword, so "On fire" and "Burning" both get the flame.
    static func symbol(for name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = symbols[key] { return exact }
        return keywordSymbols.first { key.contains($0.keyword) }?.symbol ?? "tag.fill"
    }

    var symbol: String { Self.symbol(for: name) }

    private static let symbols: [String: String] = [
        "blinded": "eye.slash",
        "charmed": "heart.fill",
        "concentrating": "brain.head.profile",
        "deafened": "speaker.slash.fill",
        "frightened": "exclamationmark.triangle.fill",
        "grappled": "hand.raised.fill",
        "incapacitated": "nosign",
        "invisible": "circle.dotted",
        "paralyzed": "bolt.fill",
        "petrified": "mountain.2.fill",
        "poisoned": "drop.triangle.fill",
        "prone": "arrow.down.to.line",
        "restrained": "link",
        "stunned": "bolt.circle.fill",
        "unconscious": "moon.zzz.fill",
        "hasted": "hare.fill",
        "blessed": "sparkles",
    ]

    private static let keywordSymbols: [(keyword: String, symbol: String)] = [
        ("exhaust", "battery.25percent"),
        ("fire", "flame.fill"), ("burn", "flame.fill"),
        ("bleed", "drop.fill"),
        ("slow", "tortoise.fill"),
        ("frozen", "snowflake"), ("cold", "snowflake"),
        ("shield", "shield.fill"), ("dodg", "shield.fill"),
        ("sleep", "moon.zzz.fill"),
        ("bane", "exclamationmark.triangle.fill"),
        ("hex", "eye.trianglebadge.exclamationmark"),
        ("curse", "eye.trianglebadge.exclamationmark"),
        ("mark", "scope"),
        ("silenc", "speaker.slash.fill"),
        ("heal", "cross.vial.fill"), ("regen", "cross.vial.fill"),
    ]
}

/// Where a combatant stands, from untouched to down. The bloodied step is the half-HP line.
enum Health: Int, Comparable {
    case down, critical, bloodied, hurt, healthy

    static func < (a: Health, b: Health) -> Bool { a.rawValue < b.rawValue }
}

/// One participant in a fight.
struct Combatant: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// `nil` until rolled. An unrolled combatant is listed but takes no turns, so the party can
    /// be added up front and slotted into the order as each player calls out their roll.
    var initiative: Int?
    /// Added to the d20 when the app rolls initiative for this combatant. Usually Dexterity.
    var initiativeBonus: Int?
    var armorClass: Int?
    /// Current hit points. Typed as a new total ("23"), or as damage or healing ("-7", "+5").
    var hp: Int?
    /// Set the first time HP is entered, and raised if a bigger total is typed. Healing stops here
    /// and "bloodied" is judged against it.
    var maxHP: Int?
    /// Player characters survive `endCombat()`; everything else is cleared with the fight.
    var isPlayer: Bool = false
    var conditions: [Condition] = []
    /// Death saving throws, tracked for anyone at 0 HP. Three of either ends it.
    var deathSuccesses: Int = 0
    var deathFailures: Int = 0
    /// The lair-actions entry: acts on initiative 20, losing every tie, with no HP or AC of its own.
    var isLair: Bool = false

    var isDown: Bool { !isLair && (hp ?? 1) <= 0 }
    /// At half HP or fewer, but still standing.
    var isBloodied: Bool {
        guard let hp, let maxHP, hp > 0, maxHP > 0 else { return false }
        return hp * 2 <= maxHP
    }
    /// How hurt, in four steps by the share of maximum HP left. `nil` when either number is not
    /// known, so there is nothing to colour.
    var health: Health? {
        guard !isLair, let hp, let maxHP, maxHP > 0 else { return nil }
        if hp <= 0 { return .down }
        let share = Double(hp) / Double(maxHP)
        switch share {
        case _ where share > 0.75: return .healthy
        case _ where share > 0.5: return .hurt
        case _ where share > 0.25: return .bloodied
        default: return .critical
        }
    }
    var isStable: Bool { deathSuccesses >= 3 }
    var isDead: Bool { deathFailures >= 3 }

    /// Decoded by hand for the same reason as `AudioLayer`: Swift's synthesized `Codable`
    /// ignores property defaults, so a field added later would orphan every file already saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed"
        initiative = try c.decodeIfPresent(Int.self, forKey: .initiative)
        initiativeBonus = try c.decodeIfPresent(Int.self, forKey: .initiativeBonus)
        armorClass = try c.decodeIfPresent(Int.self, forKey: .armorClass)
        hp = try c.decodeIfPresent(Int.self, forKey: .hp)
        maxHP = try c.decodeIfPresent(Int.self, forKey: .maxHP)
        isPlayer = try c.decodeIfPresent(Bool.self, forKey: .isPlayer) ?? false
        conditions = try c.decodeIfPresent([Condition].self, forKey: .conditions) ?? []
        deathSuccesses = try c.decodeIfPresent(Int.self, forKey: .deathSuccesses) ?? 0
        deathFailures = try c.decodeIfPresent(Int.self, forKey: .deathFailures) ?? 0
        isLair = try c.decodeIfPresent(Bool.self, forKey: .isLair) ?? false
    }

    init(name: String, initiative: Int? = nil, armorClass: Int? = nil, hp: Int? = nil,
         isPlayer: Bool = false, initiativeBonus: Int? = nil, isLair: Bool = false) {
        self.name = name
        self.initiative = initiative
        self.initiativeBonus = initiativeBonus
        self.armorClass = armorClass
        self.hp = hp
        self.maxHP = hp
        self.isPlayer = isPlayer
        self.isLair = isLair
    }
}

/// A monster, or a group of them, prepared ahead of a fight. Turned into combatants when the
/// encounter is loaded onto the table.
struct PlannedMonster: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// More than one is numbered — "Goblin 1", "Goblin 2" — each with its own copy of the HP.
    var count: Int = 1
    var armorClass: Int?
    var hp: Int?
    var initiativeBonus: Int?

    init(name: String, count: Int = 1, armorClass: Int? = nil, hp: Int? = nil,
         initiativeBonus: Int? = nil) {
        self.name = name
        self.count = count
        self.armorClass = armorClass
        self.hp = hp
        self.initiativeBonus = initiativeBonus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Monster"
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        armorClass = try c.decodeIfPresent(Int.self, forKey: .armorClass)
        hp = try c.decodeIfPresent(Int.self, forKey: .hp)
        initiativeBonus = try c.decodeIfPresent(Int.self, forKey: .initiativeBonus)
    }
}

/// One fight of the session, prepared in advance: who is in it and which sound scene plays when
/// it starts. The party is not part of an encounter — it is the same table all the way through,
/// so the characters carry their HP from one fight to the next.
struct Encounter: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var monsters: [PlannedMonster] = []
    /// Started when combat starts, unless it is already playing.
    var sceneID: UUID?
    /// Set when the fight is ended, so a list of them shows how far the session has got.
    var done: Bool = false

    init(name: String, monsters: [PlannedMonster] = [], sceneID: UUID? = nil) {
        self.name = name
        self.monsters = monsters
        self.sceneID = sceneID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Encounter"
        monsters = try c.decodeIfPresent([PlannedMonster].self, forKey: .monsters) ?? []
        sceneID = try c.decodeIfPresent(UUID.self, forKey: .sceneID)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }

    /// Monsters in the encounter, counting each member of a group.
    var headcount: Int { monsters.reduce(0) { $0 + max($1.count, 1) } }
}

/// What `combat.json` holds. `round == 0` means the fight has not started.
struct CombatSnapshot: Codable {
    var combatants: [Combatant] = []
    var round: Int = 0
    var currentID: UUID?
    var encounters: [Encounter] = []
    /// The encounter whose monsters are on the table.
    var activeEncounterID: UUID?

    init(combatants: [Combatant] = [], round: Int = 0, currentID: UUID? = nil,
         encounters: [Encounter] = [], activeEncounterID: UUID? = nil) {
        self.combatants = combatants
        self.round = round
        self.currentID = currentID
        self.encounters = encounters
        self.activeEncounterID = activeEncounterID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        combatants = try c.decodeIfPresent([Combatant].self, forKey: .combatants) ?? []
        round = try c.decodeIfPresent(Int.self, forKey: .round) ?? 0
        currentID = try c.decodeIfPresent(UUID.self, forKey: .currentID)
        encounters = try c.decodeIfPresent([Encounter].self, forKey: .encounters) ?? []
        activeEncounterID = try c.decodeIfPresent(UUID.self, forKey: .activeEncounterID)
    }
}

enum CombatArchive {
    static func load() -> CombatSnapshot {
        switch JSONStore.load(CombatSnapshot.self, from: Vault.combatFile) {
        case .ok(let snapshot): return snapshot
        case .missing, .damaged: return CombatSnapshot()
        }
    }

    static func save(_ snapshot: CombatSnapshot) {
        JSONStore.save(snapshot, to: Vault.combatFile)
    }
}

/// How an HP field's text is read: a bare number is a new total, a leading sign is a change.
enum HPEntry: Equatable {
    case set(Int)
    case change(Int)

    /// "23" sets, "-7" is damage, "+5" is healing. Anything else is not an entry.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }
        if first == "+" || first == "-" || first == "−" {
            // "−" is what some keyboards and autocorrect produce for a minus.
            let digits = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let n = Int(digits) else { return nil }
            self = .change(first == "+" ? n : -n)
        } else if let n = Int(trimmed) {
            self = .set(n)
        } else {
            return nil
        }
    }
}

/// The fight in progress: who is in it, in what order, and whose turn it is.
///
/// `combatants` is kept in *entry* order and the initiative order is derived from it, so ties
/// resolve to whoever was added first and stay put while other rows are edited. Every mutation
/// is written straight to disk — a relaunch mid-fight must come back to the same turn.
@MainActor
@Observable
final class CombatTracker {
    private(set) var combatants: [Combatant] = []
    private(set) var round = 0
    private(set) var currentID: UUID?
    private(set) var encounters: [Encounter] = []
    private(set) var activeEncounterID: UUID?
    /// Snapshots from before each change, newest last, so a stray click is not a disaster.
    private(set) var undoStack: [CombatSnapshot] = []

    /// Notable moments, phrased for a session log: "Round 3", "Kaela dropped to 0 HP".
    @ObservationIgnored var onEvent: ((String) -> Void)?
    /// Called as the first turn begins, with the encounter on the table if there is one.
    @ObservationIgnored var onStart: ((Encounter?) -> Void)?

    @ObservationIgnored private static let undoLimit = 60

    init() {
        Vault.bootstrap()
        reload()
    }

    var isRunning: Bool { round > 0 }
    var canUndo: Bool { !undoStack.isEmpty }

    /// Highest initiative first; ties keep entry order, except that lair actions lose every tie;
    /// the unrolled go last.
    var order: [Combatant] {
        combatants.enumerated().sorted { a, b in
            switch (a.element.initiative, b.element.initiative) {
            case let (x?, y?):
                if x != y { return x > y }
                if a.element.isLair != b.element.isLair { return b.element.isLair }
                return a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Only those who have rolled take turns.
    var turnOrder: [Combatant] { order.filter { $0.initiative != nil } }

    var current: Combatant? { combatants.first { $0.id == currentID } }

    var hasLair: Bool { combatants.contains { $0.isLair } }

    /// `nil` once the encounter has been deleted, even if the id is still on file.
    var activeEncounter: Encounter? { encounters.first { $0.id == activeEncounterID } }

    func reload() {
        let snapshot = CombatArchive.load()
        combatants = snapshot.combatants
        round = snapshot.round
        currentID = snapshot.currentID
        encounters = snapshot.encounters
        activeEncounterID = snapshot.activeEncounterID
        undoStack = []

        // A file edited by hand, or an older one, can leave the turn pointing at nobody.
        if isRunning, !turnOrder.contains(where: { $0.id == currentID }) {
            if let first = turnOrder.first { currentID = first.id } else { stop() }
        }
    }

    // MARK: Undo

    private var snapshot: CombatSnapshot {
        CombatSnapshot(combatants: combatants, round: round, currentID: currentID,
                       encounters: encounters, activeEncounterID: activeEncounterID)
    }

    private func checkpoint() {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
    }

    /// Puts the table back as it was before the last change. Encounters are prepared outside the
    /// fight, so what is written into them stays — only which one is loaded, and which are done,
    /// goes back.
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        combatants = previous.combatants
        round = previous.round
        currentID = previous.currentID
        activeEncounterID = previous.activeEncounterID
        let wasDone = Dictionary(uniqueKeysWithValues: previous.encounters.map { ($0.id, $0.done) })
        for i in encounters.indices {
            if let done = wasDone[encounters[i].id] { encounters[i].done = done }
        }
        persist()
    }

    // MARK: Dice

    static func rollD20(bonus: Int? = nil) -> Int { Int.random(in: 1...20) + (bonus ?? 0) }

    /// Rolls d20 + bonus for one combatant, replacing any initiative they had.
    func rollInitiative(_ id: UUID) {
        update(id) { $0.initiative = Self.rollD20(bonus: $0.initiativeBonus) }
    }

    /// Rolls for every NPC who has not rolled yet — the party calls out its own.
    func rollNPCInitiative() {
        let pending = combatants.filter { !$0.isPlayer && !$0.isLair && $0.initiative == nil }
        guard !pending.isEmpty else { return }
        checkpoint()
        for combatant in pending {
            if let i = combatants.firstIndex(where: { $0.id == combatant.id }) {
                combatants[i].initiative = Self.rollD20(bonus: combatants[i].initiativeBonus)
            }
        }
        persist()
    }

    var hasUnrolledNPCs: Bool {
        combatants.contains { !$0.isPlayer && !$0.isLair && $0.initiative == nil }
    }

    // MARK: Roster

    /// `count > 1` adds a numbered group — "Goblin 1", "Goblin 2". With `groupInitiative` the group
    /// shares one initiative (the DMG's optional rule, and quicker at the table); without it each
    /// rolls its own d20 plus `initiativeBonus`. Each row is its own copy either way, so HP
    /// diverges as the fight goes on.
    func add(name: String, initiative: Int?, armorClass: Int?, hp: Int? = nil, isPlayer: Bool,
             count: Int = 1, initiativeBonus: Int? = nil, groupInitiative: Bool = true) {
        let base = name.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return }
        checkpoint()
        let n = min(max(count, 1), 30)
        for i in 1...n {
            let rollsOwn = n > 1 && !groupInitiative
            combatants.append(Combatant(name: n > 1 ? "\(base) \(i)" : base,
                                        initiative: rollsOwn ? Self.rollD20(bonus: initiativeBonus)
                                                             : initiative,
                                        armorClass: armorClass,
                                        hp: hp,
                                        isPlayer: isPlayer,
                                        initiativeBonus: initiativeBonus))
        }
        persist()
    }

    /// The lair-actions entry, on initiative 20. Losing ties is built into the ordering.
    func addLair() {
        guard !hasLair else { return }
        checkpoint()
        combatants.append(Combatant(name: "Lair actions", initiative: 20, isLair: true))
        persist()
    }

    func update(_ id: UUID, _ change: (inout Combatant) -> Void) {
        guard let i = combatants.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        var edited = combatants[i]
        let wasDown = edited.isDown
        change(&edited)

        // Un-rolling whoever is up takes them out of the rotation, so pass the turn first.
        if id == currentID, edited.initiative == nil { passTurn(from: id) }

        combatants[i] = edited
        persist()

        if edited.isDown && !wasDown { onEvent?("\(edited.name) dropped to 0 HP") }
    }

    /// Applies what was typed in an HP field: a total, or `-7` / `+5`.
    func enterHP(_ id: UUID, _ text: String) {
        guard let entry = HPEntry(text) else { return }
        update(id) { c in
            switch entry {
            case .set(let value):
                let hp = max(0, value)
                c.hp = hp
                // The first number typed is the maximum; a later bigger one raises it.
                c.maxHP = max(c.maxHP ?? 0, hp)
            case .change(let delta):
                let base = c.hp ?? c.maxHP ?? 0
                var hp = max(0, base + delta)
                if delta > 0, let cap = c.maxHP { hp = min(hp, max(cap, base)) }
                c.hp = hp
                if c.maxHP == nil { c.maxHP = max(base, hp) }
            }
            if (c.hp ?? 0) > 0 {
                c.deathSuccesses = 0
                c.deathFailures = 0
            }
        }
    }

    func setDeathSaves(_ id: UUID, successes: Int, failures: Int) {
        var died: String?
        update(id) { c in
            let wasDead = c.isDead
            c.deathSuccesses = min(max(successes, 0), 3)
            c.deathFailures = min(max(failures, 0), 3)
            if c.isDead && !wasDead { died = c.name }
        }
        if let died { onEvent?("\(died) died") }
    }

    func addCondition(_ id: UUID, name: String, rounds: Int?) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        update(id) { c in
            // Re-applying replaces, so refreshing a duration does not stack a second copy.
            c.conditions.removeAll { $0.name.caseInsensitiveCompare(clean) == .orderedSame }
            c.conditions.append(Condition(name: clean, rounds: rounds))
        }
    }

    func removeCondition(_ id: UUID, conditionID: UUID) {
        update(id) { $0.conditions.removeAll { $0.id == conditionID } }
    }

    func remove(_ id: UUID) {
        checkpoint()
        if id == currentID { passTurn(from: id) }
        combatants.removeAll { $0.id == id }
        persist()
    }

    /// Swap with the neighbour at the *same* initiative, in the given direction. Dice cannot
    /// break a tie, so the DM does — and the order is derived from entry order, so a swap in
    /// the roster is the whole implementation.
    func swapTie(_ id: UUID, direction: Int) {
        guard canSwapTie(id, direction: direction) else { return }
        let sorted = order
        guard let at = sorted.firstIndex(where: { $0.id == id }),
              let a = combatants.firstIndex(where: { $0.id == id }),
              let b = combatants.firstIndex(where: { $0.id == sorted[at + direction].id })
        else { return }
        checkpoint()
        combatants.swapAt(a, b)
        persist()
    }

    /// Lair actions are pinned last in their tie, so they are never swapped.
    func canSwapTie(_ id: UUID, direction: Int) -> Bool {
        let sorted = order
        guard let at = sorted.firstIndex(where: { $0.id == id }),
              sorted[at].initiative != nil,
              sorted.indices.contains(at + direction)
        else { return false }
        let neighbour = sorted[at + direction]
        return neighbour.initiative == sorted[at].initiative
            && !neighbour.isLair && !sorted[at].isLair
    }

    /// After a fight: monsters go, the party stays with its initiative cleared for next time.
    /// HP and AC are kept — the DM adjusts the party's HP by hand between fights. Conditions end
    /// with the fight.
    func endCombat() {
        checkpoint()
        let wasRunning = isRunning
        let finalRound = round
        let finished = activeEncounter
        if let finished { updateEncounterSilently(finished.id) { $0.done = true } }
        activeEncounterID = nil
        combatants.removeAll { !$0.isPlayer }
        for i in combatants.indices {
            combatants[i].initiative = nil
            combatants[i].conditions = []
        }
        stop()
        persist()
        if wasRunning {
            let name = finished.map { " — \($0.name)" } ?? ""
            onEvent?("Combat ended after \(finalRound) round\(finalRound == 1 ? "" : "s")\(name)")
        }
    }

    func clearAll() {
        checkpoint()
        combatants = []
        activeEncounterID = nil
        stop()
        persist()
    }

    // MARK: Encounters

    @discardableResult
    func addEncounter(name: String) -> UUID {
        let clean = name.trimmingCharacters(in: .whitespaces)
        let encounter = Encounter(name: clean.isEmpty ? "Encounter \(encounters.count + 1)" : clean)
        encounters.append(encounter)
        persist()
        return encounter.id
    }

    /// Editing a prepared encounter is not part of the fight, so it is not undoable.
    func updateEncounter(_ id: UUID, _ change: (inout Encounter) -> Void) {
        guard let i = encounters.firstIndex(where: { $0.id == id }) else { return }
        change(&encounters[i])
        persist()
    }

    func removeEncounter(_ id: UUID) {
        encounters.removeAll { $0.id == id }
        // Its monsters stay on the table as ordinary combatants.
        if activeEncounterID == id { activeEncounterID = nil }
        persist()
    }

    /// Puts an encounter's monsters on the table in place of the last fight's. The party stays as
    /// it is — HP and all. If a fight is running it stops, and the party's initiative and
    /// conditions are cleared for the new one; before the first turn they are left alone, since
    /// the players may already have called out their rolls.
    func load(_ id: UUID) {
        guard let encounter = encounters.first(where: { $0.id == id }) else { return }
        checkpoint()
        if isRunning {
            for i in combatants.indices {
                combatants[i].initiative = nil
                combatants[i].conditions = []
            }
            stop()
        }
        combatants.removeAll { !$0.isPlayer }
        for planned in encounter.monsters {
            let n = min(max(planned.count, 1), 30)
            for i in 1...n {
                combatants.append(Combatant(name: n > 1 ? "\(planned.name) \(i)" : planned.name,
                                            armorClass: planned.armorClass,
                                            hp: planned.hp,
                                            isPlayer: false,
                                            initiativeBonus: planned.initiativeBonus))
            }
        }
        activeEncounterID = id
        persist()
        onEvent?("Encounter: \(encounter.name)")
    }

    // MARK: Turns

    /// Starts the fight if it hasn't begun, otherwise moves to the next combatant, opening a
    /// new round when the order wraps. Leaving someone ends their turn: their timed conditions
    /// tick down.
    func next() {
        let order = turnOrder
        guard !order.isEmpty else { return }
        checkpoint()
        guard isRunning, let id = currentID,
              let at = order.firstIndex(where: { $0.id == id })
        else {
            round = max(round, 1)
            currentID = order[0].id
            persist()
            let name = activeEncounter.map { "\($0.name): " } ?? ""
            onEvent?("Combat started — \(name)\(order.count) in the order")
            onStart?(activeEncounter)
            return
        }

        let expired = tickConditions(of: id)

        if at + 1 < order.count {
            currentID = order[at + 1].id
        } else {
            round += 1
            currentID = order[0].id
            onEvent?("Round \(round)")
        }
        persist()
        for line in expired { onEvent?(line) }
    }

    /// Steps back, including into the previous round. Does nothing at the very first turn. A
    /// condition that expired on the way forward does not come back — that is what undo is for.
    func previous() {
        let order = turnOrder
        guard isRunning, let id = currentID,
              let at = order.firstIndex(where: { $0.id == id })
        else { return }
        if at > 0 {
            checkpoint()
            currentID = order[at - 1].id
        } else if round > 1 {
            checkpoint()
            round -= 1
            currentID = order[order.count - 1].id
        } else {
            return
        }
        persist()
    }

    /// Counts down the timed conditions of whoever just finished, returning a line for each that
    /// ran out.
    private func tickConditions(of id: UUID) -> [String] {
        guard let i = combatants.firstIndex(where: { $0.id == id }) else { return [] }
        var ended: [String] = []
        var kept: [Condition] = []
        for var condition in combatants[i].conditions {
            if let rounds = condition.rounds {
                if rounds <= 1 {
                    ended.append("\(combatants[i].name) is no longer \(condition.name.lowercased())")
                    continue
                }
                condition.rounds = rounds - 1
            }
            kept.append(condition)
        }
        combatants[i].conditions = kept
        return ended
    }

    /// Hands the turn to whoever follows `id` — without persisting, because the caller is
    /// mid-mutation and writes once at the end. If `id` is the last to act the new round opens,
    /// and if nobody else can act the fight stops.
    private func passTurn(from id: UUID) {
        let order = turnOrder
        guard order.contains(where: { $0.id == id }) else { return }
        guard order.count > 1, let at = order.firstIndex(where: { $0.id == id }) else {
            stop()
            return
        }
        if at + 1 < order.count {
            currentID = order[at + 1].id
        } else {
            round += 1
            currentID = order[0].id
        }
    }

    /// `updateEncounter` without the write, for a caller that persists once at the end.
    private func updateEncounterSilently(_ id: UUID, _ change: (inout Encounter) -> Void) {
        guard let i = encounters.firstIndex(where: { $0.id == id }) else { return }
        change(&encounters[i])
    }

    private func stop() {
        round = 0
        currentID = nil
    }

    private func persist() {
        CombatArchive.save(snapshot)
    }
}
