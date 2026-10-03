import Combine
import Foundation

/// One participant in a fight.
struct Combatant: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// `nil` until rolled. An unrolled combatant is listed but takes no turns, so the party can
    /// be added up front and slotted into the order as each player calls out their roll.
    var initiative: Int?
    var armorClass: Int?
    /// Current hit points. A single number rather than current/max: the DM types the new total
    /// as damage lands, and what matters at the table is how close each creature is to dropping.
    var hp: Int?
    /// Player characters survive `endCombat()`; everything else is cleared with the fight.
    var isPlayer: Bool = false

    /// Decoded by hand for the same reason as `AudioLayer`: Swift's synthesized `Codable`
    /// ignores property defaults, so a field added later would orphan every file already saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed"
        initiative = try c.decodeIfPresent(Int.self, forKey: .initiative)
        armorClass = try c.decodeIfPresent(Int.self, forKey: .armorClass)
        hp = try c.decodeIfPresent(Int.self, forKey: .hp)
        isPlayer = try c.decodeIfPresent(Bool.self, forKey: .isPlayer) ?? false
    }

    init(name: String, initiative: Int? = nil, armorClass: Int? = nil, hp: Int? = nil,
         isPlayer: Bool = false) {
        self.name = name
        self.initiative = initiative
        self.armorClass = armorClass
        self.hp = hp
        self.isPlayer = isPlayer
    }
}

/// What `combat.json` holds. `round == 0` means the fight has not started.
struct CombatSnapshot: Codable {
    var combatants: [Combatant] = []
    var round: Int = 0
    var currentID: UUID?

    init(combatants: [Combatant] = [], round: Int = 0, currentID: UUID? = nil) {
        self.combatants = combatants
        self.round = round
        self.currentID = currentID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        combatants = try c.decodeIfPresent([Combatant].self, forKey: .combatants) ?? []
        round = try c.decodeIfPresent(Int.self, forKey: .round) ?? 0
        currentID = try c.decodeIfPresent(UUID.self, forKey: .currentID)
    }
}

enum CombatArchive {
    static func load() -> CombatSnapshot {
        guard let data = try? Data(contentsOf: Vault.combatFile),
              let snapshot = try? JSONDecoder().decode(CombatSnapshot.self, from: data)
        else { return CombatSnapshot() }
        return snapshot
    }

    static func save(_ snapshot: CombatSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(snapshot).write(to: Vault.combatFile, options: .atomic)
    }
}

/// The fight in progress: who is in it, in what order, and whose turn it is.
///
/// `combatants` is kept in *entry* order and the initiative order is derived from it, so ties
/// resolve to whoever was added first and stay put while other rows are edited. Every mutation
/// is written straight to disk — a relaunch mid-fight must come back to the same turn.
@MainActor
final class CombatTracker: ObservableObject {
    @Published private(set) var combatants: [Combatant] = []
    @Published private(set) var round = 0
    @Published private(set) var currentID: UUID?

    init() {
        Vault.bootstrap()
        reload()
    }

    var isRunning: Bool { round > 0 }

    /// Highest initiative first; ties keep entry order; the unrolled go last.
    var order: [Combatant] {
        combatants.enumerated().sorted { a, b in
            switch (a.element.initiative, b.element.initiative) {
            case let (x?, y?): return x != y ? x > y : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Only those who have rolled take turns.
    var turnOrder: [Combatant] { order.filter { $0.initiative != nil } }

    var current: Combatant? { combatants.first { $0.id == currentID } }

    func reload() {
        let snapshot = CombatArchive.load()
        combatants = snapshot.combatants
        round = snapshot.round
        currentID = snapshot.currentID

        // A file edited by hand, or an older one, can leave the turn pointing at nobody.
        if isRunning, !turnOrder.contains(where: { $0.id == currentID }) {
            if let first = turnOrder.first { currentID = first.id } else { stop() }
        }
    }

    // MARK: Roster

    /// `count > 1` adds a numbered group — "Goblin 1", "Goblin 2" — sharing initiative, AC and
    /// starting HP (initiative rolled once per group, as the rules suggest). Each row is its own
    /// copy, so HP then diverges as the fight goes on.
    func add(name: String, initiative: Int?, armorClass: Int?, hp: Int? = nil, isPlayer: Bool,
             count: Int = 1) {
        let base = name.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return }
        let n = min(max(count, 1), 30)
        for i in 1...n {
            combatants.append(Combatant(name: n > 1 ? "\(base) \(i)" : base,
                                        initiative: initiative,
                                        armorClass: armorClass,
                                        hp: hp,
                                        isPlayer: isPlayer))
        }
        persist()
    }

    func update(_ id: UUID, _ change: (inout Combatant) -> Void) {
        guard let i = combatants.firstIndex(where: { $0.id == id }) else { return }
        var edited = combatants[i]
        change(&edited)

        // Un-rolling whoever is up takes them out of the rotation, so pass the turn first.
        if id == currentID, edited.initiative == nil { passTurn(from: id) }

        combatants[i] = edited
        persist()
    }

    func remove(_ id: UUID) {
        if id == currentID { passTurn(from: id) }
        combatants.removeAll { $0.id == id }
        persist()
    }

    /// Swap with the neighbour at the *same* initiative, in the given direction. Dice cannot
    /// break a tie, so the DM does — and the order is derived from entry order, so a swap in
    /// the roster is the whole implementation.
    func swapTie(_ id: UUID, direction: Int) {
        let sorted = order
        guard let at = sorted.firstIndex(where: { $0.id == id }),
              sorted[at].initiative != nil,
              sorted.indices.contains(at + direction),
              sorted[at + direction].initiative == sorted[at].initiative,
              let a = combatants.firstIndex(where: { $0.id == id }),
              let b = combatants.firstIndex(where: { $0.id == sorted[at + direction].id })
        else { return }
        combatants.swapAt(a, b)
        persist()
    }

    func canSwapTie(_ id: UUID, direction: Int) -> Bool {
        let sorted = order
        guard let at = sorted.firstIndex(where: { $0.id == id }),
              sorted[at].initiative != nil,
              sorted.indices.contains(at + direction)
        else { return false }
        return sorted[at + direction].initiative == sorted[at].initiative
    }

    /// After a fight: monsters go, the party stays with its initiative cleared for next time.
    /// HP and AC are kept — the DM adjusts the party's HP by hand between fights.
    func endCombat() {
        combatants.removeAll { !$0.isPlayer }
        for i in combatants.indices { combatants[i].initiative = nil }
        stop()
        persist()
    }

    func clearAll() {
        combatants = []
        stop()
        persist()
    }

    // MARK: Turns

    /// Starts the fight if it hasn't begun, otherwise moves to the next combatant, opening a
    /// new round when the order wraps.
    func next() {
        let order = turnOrder
        guard !order.isEmpty else { return }
        guard isRunning, let id = currentID,
              let at = order.firstIndex(where: { $0.id == id })
        else {
            round = max(round, 1)
            currentID = order[0].id
            persist()
            return
        }
        if at + 1 < order.count {
            currentID = order[at + 1].id
        } else {
            round += 1
            currentID = order[0].id
        }
        persist()
    }

    /// Steps back, including into the previous round. Does nothing at the very first turn.
    func previous() {
        let order = turnOrder
        guard isRunning, let id = currentID,
              let at = order.firstIndex(where: { $0.id == id })
        else { return }
        if at > 0 {
            currentID = order[at - 1].id
        } else if round > 1 {
            round -= 1
            currentID = order[order.count - 1].id
        } else {
            return
        }
        persist()
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

    private func stop() {
        round = 0
        currentID = nil
    }

    private func persist() {
        CombatArchive.save(CombatSnapshot(combatants: combatants, round: round, currentID: currentID))
    }
}
