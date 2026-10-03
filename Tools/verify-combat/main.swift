import AppKit
import Foundation

@main
struct Probe {
    @MainActor
    static func main() async {
        let vault = CommandLine.arguments[1]
        UserDefaults.standard.set(vault, forKey: "vault.path")
        Vault.bootstrap()

        var fails = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("  \(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { fails += 1 }
        }
        func names(_ list: [Combatant]) -> String { list.map(\.name).joined(separator: ", ") }

        let t = CombatTracker()
        check("starts empty and not running", t.combatants.isEmpty && !t.isRunning)

        // Entered out of order, with a tie at 15 and one still unrolled.
        t.add(name: "Mira", initiative: 12, armorClass: 16, hp: 28, isPlayer: true)
        t.add(name: "Thane", initiative: 15, armorClass: 18, hp: 41, isPlayer: true)
        t.add(name: "Goblin", initiative: 15, armorClass: 13, hp: 7, isPlayer: false, count: 3)
        t.add(name: "Ogre", initiative: nil, armorClass: 11, isPlayer: false)
        check("group is numbered", t.combatants.map(\.name).contains("Goblin 3"), names(t.combatants))
        check("order: highest first, ties in entry order, unrolled last",
              names(t.order) == "Thane, Goblin 1, Goblin 2, Goblin 3, Mira, Ogre", names(t.order))
        check("unrolled take no turns", names(t.turnOrder) == "Thane, Goblin 1, Goblin 2, Goblin 3, Mira")
        check("armor class kept", t.combatants.first { $0.name == "Thane" }?.armorClass == 18)
        check("hp kept", t.combatants.first { $0.name == "Thane" }?.hp == 41)
        check("a group starts with the same hp each",
              t.combatants.filter { $0.name.hasPrefix("Goblin") }.allSatisfy { $0.hp == 7 })
        let g2 = t.combatants.first { $0.name == "Goblin 2" }!.id
        t.update(g2) { $0.hp = 0 }
        check("hp edits one row of a group, not the rest",
              t.combatants.first { $0.name == "Goblin 2" }?.hp == 0
                  && t.combatants.first { $0.name == "Goblin 1" }?.hp == 7)

        // Turns and rounds.
        t.next()
        check("first next starts round 1 on the top of the order",
              t.round == 1 && t.current?.name == "Thane")
        for _ in 0..<4 { t.next() }
        check("walks the order to the last combatant", t.current?.name == "Mira" && t.round == 1)
        t.next()
        check("wrapping opens round 2 at the top", t.round == 2 && t.current?.name == "Thane")
        t.previous()
        check("previous steps back into round 1", t.round == 1 && t.current?.name == "Mira")
        t.previous(); t.previous(); t.previous(); t.previous()
        check("previous stops at the very first turn",
              t.round == 1 && t.current?.name == "Thane")
        t.previous()
        check("previous at the first turn is a no-op", t.round == 1 && t.current?.name == "Thane")

        // Persistence across a simulated relaunch, mid-fight.
        let relaunched = CombatTracker()
        check("relaunch keeps roster", relaunched.combatants.count == t.combatants.count)
        check("relaunch keeps round and turn",
              relaunched.round == 1 && relaunched.current?.name == "Thane")

        // Removing whoever is up passes the turn without skipping anyone.
        t.next()                       // Goblin 1
        let goblin1 = t.current!.id
        t.remove(goblin1)
        check("removing the current combatant hands over to the next",
              t.current?.name == "Goblin 2" && t.round == 1, t.current?.name ?? "none")
        t.next(); t.next()             // Goblin 3, then Mira
        t.remove(t.current!.id)        // Mira, the last to act
        check("removing the last to act opens the next round",
              t.round == 2 && t.current?.name == "Thane", "round \(t.round), \(t.current?.name ?? "none")")

        // Un-rolling whoever is up also takes them out of the rotation.
        t.update(t.current!.id) { $0.initiative = nil }
        check("un-rolling the current combatant passes the turn",
              t.current?.name != "Thane" && t.current != nil, t.current?.name ?? "none")

        // Re-rolling reorders without moving the turn.
        let holder = t.current!.id
        t.update(t.combatants.first { $0.name == "Thane" }!.id) { $0.initiative = 30 }
        check("editing initiative re-sorts", t.order.first?.name == "Thane")
        check("editing initiative leaves the turn where it was", t.currentID == holder)

        // Tie-breaking by hand.
        let tied = CombatTracker()
        tied.clearAll()
        tied.add(name: "A", initiative: 10, armorClass: nil, isPlayer: false)
        tied.add(name: "B", initiative: 10, armorClass: nil, isPlayer: false)
        tied.add(name: "C", initiative: 9, armorClass: nil, isPlayer: false)
        let b = tied.combatants[1].id
        check("only a tied neighbour can be swapped",
              tied.canSwapTie(b, direction: -1) && !tied.canSwapTie(b, direction: 1))
        tied.swapTie(b, direction: -1)
        check("swap breaks the tie", names(tied.order) == "B, A, C", names(tied.order))
        tied.swapTie(tied.combatants.first { $0.name == "C" }!.id, direction: -1)
        check("a swap across different initiatives is refused", names(tied.order) == "B, A, C")

        // Last combatant removed stops the fight rather than leaving a dangling turn.
        let solo = CombatTracker()
        solo.clearAll()
        solo.add(name: "Lone", initiative: 10, armorClass: nil, isPlayer: false)
        solo.next()
        solo.remove(solo.current!.id)
        check("removing the only combatant ends the fight", !solo.isRunning && solo.current == nil)

        // End combat keeps the party.
        let end = CombatTracker()
        end.clearAll()
        end.add(name: "Mira", initiative: 12, armorClass: 16, hp: 28, isPlayer: true)
        end.add(name: "Orc", initiative: 8, armorClass: 13, isPlayer: false)
        end.next()
        end.endCombat()
        check("end combat removes monsters, keeps the party",
              names(end.combatants) == "Mira", names(end.combatants))
        check("end combat clears initiative and stops",
              end.combatants[0].initiative == nil && !end.isRunning)
        check("end combat keeps armor class and hp",
              end.combatants[0].armorClass == 16 && end.combatants[0].hp == 28)

        // MARK: HP entry — a total, damage, or healing
        check("HP text: a bare number is a total", HPEntry("23") == .set(23))
        check("HP text: a minus is damage", HPEntry("-7") == .change(-7))
        check("HP text: a plus is healing", HPEntry("+5") == .change(5))
        check("HP text: the Unicode minus works too", HPEntry("−3") == .change(-3))
        check("HP text: junk is not an entry", HPEntry("abc") == nil && HPEntry("") == nil && HPEntry("-") == nil)

        let hpT = CombatTracker()
        hpT.clearAll()
        var events: [String] = []
        hpT.onEvent = { events.append($0) }
        hpT.add(name: "Orc", initiative: 10, armorClass: 13, hp: 20, isPlayer: false)
        let orc = hpT.combatants[0].id
        func orcNow() -> Combatant { hpT.combatants.first { $0.id == orc }! }
        check("the HP typed at entry is also the maximum", orcNow().hp == 20 && orcNow().maxHP == 20)
        hpT.enterHP(orc, "-7")
        check("−7 is damage", orcNow().hp == 13)
        hpT.enterHP(orc, "+100")
        check("healing stops at the maximum", orcNow().hp == 20, "\(orcNow().hp ?? -1)")
        hpT.enterHP(orc, "11")
        check("a bare number sets the total", orcNow().hp == 11 && orcNow().isBloodied == false)
        hpT.enterHP(orc, "10")
        check("half HP or fewer is bloodied", orcNow().isBloodied)
        hpT.enterHP(orc, "-50")
        check("damage cannot go below zero", orcNow().hp == 0 && orcNow().isDown)
        check("dropping to zero is reported", events.contains("Orc dropped to 0 HP"), events.joined(separator: "|"))
        hpT.enterHP(orc, "30")
        check("a bigger total raises the maximum", orcNow().hp == 30 && orcNow().maxHP == 30)

        // MARK: Death saves
        let pcT = CombatTracker()
        pcT.clearAll()
        var pcEvents: [String] = []
        pcT.onEvent = { pcEvents.append($0) }
        pcT.add(name: "Kaela", initiative: 14, armorClass: 15, hp: 30, isPlayer: true)
        let kaela = pcT.combatants[0].id
        func kaelaNow() -> Combatant { pcT.combatants.first { $0.id == kaela }! }
        pcT.enterHP(kaela, "-40")
        check("a player at 0 is down", kaelaNow().isDown)
        pcT.setDeathSaves(kaela, successes: 2, failures: 1)
        check("saves are recorded", kaelaNow().deathSuccesses == 2 && kaelaNow().deathFailures == 1)
        pcT.setDeathSaves(kaela, successes: 2, failures: 9)
        check("saves cap at three, and three failures is death",
              kaelaNow().deathFailures == 3 && kaelaNow().isDead && pcEvents.contains("Kaela died"))
        pcT.setDeathSaves(kaela, successes: 3, failures: 0)
        check("three successes is stable", kaelaNow().isStable)
        pcT.enterHP(kaela, "+4")
        check("healing clears the death saves",
              kaelaNow().hp == 4 && kaelaNow().deathSuccesses == 0 && kaelaNow().deathFailures == 0)

        // MARK: Conditions count down as their owner's turn ends
        let cond = CombatTracker()
        cond.clearAll()
        var condEvents: [String] = []
        cond.onEvent = { condEvents.append($0) }
        cond.add(name: "A", initiative: 15, armorClass: 10, isPlayer: false)
        cond.add(name: "B", initiative: 10, armorClass: 10, isPlayer: false)
        let aID = cond.combatants[0].id
        cond.addCondition(aID, name: "Stunned", rounds: 2)
        cond.addCondition(aID, name: "Concentrating", rounds: nil)
        func a() -> Combatant { cond.combatants.first { $0.id == aID }! }
        check("conditions are added", a().conditions.map(\.name) == ["Stunned", "Concentrating"])
        cond.addCondition(aID, name: "stunned", rounds: 3)
        check("re-applying replaces rather than stacks",
              a().conditions.filter { $0.name.lowercased() == "stunned" }.count == 1
                  && a().conditions.first { $0.name.lowercased() == "stunned" }?.rounds == 3)
        cond.addCondition(aID, name: "Stunned", rounds: 2)
        cond.next()                                    // A's turn begins
        cond.next()                                    // A ends: 2 -> 1
        check("a timed condition drops by one when its owner's turn ends",
              a().conditions.first { $0.name == "Stunned" }?.rounds == 1)
        cond.next()                                    // B ends, round 2
        check("other creatures' turns do not tick it",
              a().conditions.first { $0.name == "Stunned" }?.rounds == 1 && cond.round == 2)
        cond.next()                                    // A ends again: gone
        check("it falls off at zero and says so", a().conditions.map(\.name) == ["Concentrating"]
                  && condEvents.contains("A is no longer stunned"), condEvents.joined(separator: "|"))
        check("an untimed condition stays", a().conditions.contains { $0.name == "Concentrating" })
        cond.endCombat()
        check("conditions end with the fight", cond.combatants.allSatisfy { $0.conditions.isEmpty })

        // MARK: Undo
        let undoT = CombatTracker()
        undoT.clearAll()
        check("clearing the table is itself undoable", undoT.canUndo)
        undoT.undo()
        undoT.clearAll()
        undoT.add(name: "Imp", initiative: 12, armorClass: 13, hp: 10, isPlayer: false)
        undoT.add(name: "Mira", initiative: 9, armorClass: 16, hp: 28, isPlayer: true)
        let imp = undoT.combatants[0].id
        undoT.remove(imp)
        check("removed", undoT.combatants.map(\.name) == ["Mira"])
        undoT.undo()
        check("undo brings back a removed combatant", Set(undoT.combatants.map(\.name)) == ["Imp", "Mira"])
        undoT.next()
        undoT.next()
        undoT.endCombat()
        check("end combat removed the NPC", undoT.combatants.map(\.name) == ["Mira"] && !undoT.isRunning)
        undoT.undo()
        check("undo reverses end combat, round and turn included",
              undoT.combatants.count == 2 && undoT.isRunning && undoT.current?.name == "Mira",
              "\(undoT.combatants.count), round \(undoT.round), \(undoT.current?.name ?? "none")")
        undoT.undo()
        check("undo reverses a turn", undoT.current?.name == "Imp")
        undoT.clearAll()
        undoT.undo()
        check("undo reverses clearing the table", undoT.combatants.count == 2)

        // MARK: Lair actions
        let lair = CombatTracker()
        lair.clearAll()
        lair.add(name: "Dragon", initiative: 20, armorClass: 19, hp: 200, isPlayer: false)
        lair.add(name: "Mira", initiative: 20, armorClass: 16, hp: 28, isPlayer: true)
        lair.addLair()
        lair.addLair()
        check("only one lair entry", lair.combatants.filter(\.isLair).count == 1)
        check("lair actions lose every tie at their initiative",
              names(lair.order) == "Dragon, Mira, Lair actions", names(lair.order))
        let lairID = lair.combatants.first { $0.isLair }!.id
        check("a lair entry is never swapped", !lair.canSwapTie(lairID, direction: -1))
        check("and no one swaps into it",
              !lair.canSwapTie(lair.combatants.first { $0.name == "Mira" }!.id, direction: 1))
        lair.rollNPCInitiative()
        check("rolling NPCs leaves the lair alone", lair.combatants.first { $0.isLair }?.initiative == 20)

        // MARK: Rolling initiative
        let roll = CombatTracker()
        roll.clearAll()
        roll.add(name: "Bandit", initiative: nil, armorClass: 12, hp: 11, isPlayer: false,
                 initiativeBonus: 2)
        roll.add(name: "Rogue", initiative: nil, armorClass: 15, hp: 30, isPlayer: true)
        check("unrolled NPCs are noticed", roll.hasUnrolledNPCs)
        roll.rollNPCInitiative()
        let bandit = roll.combatants.first { $0.name == "Bandit" }!
        check("an NPC rolls d20 + its bonus", (bandit.initiative ?? 0) >= 3 && (bandit.initiative ?? 99) <= 22,
              "\(bandit.initiative ?? -1)")
        check("the party is left to call out its own",
              roll.combatants.first { $0.name == "Rogue" }?.initiative == nil)
        check("nothing left to roll", !roll.hasUnrolledNPCs)
        var seen = Set<Int>()
        for _ in 0..<200 { seen.insert(CombatTracker.rollD20()) }
        check("d20 covers 1 through 20 and nothing else", seen.min() == 1 && seen.max() == 20 && seen.count == 20,
              "\(seen.min() ?? 0)…\(seen.max() ?? 0), \(seen.count) values")

        roll.clearAll()
        roll.add(name: "Wolf", initiative: 17, armorClass: 13, hp: 11, isPlayer: false, count: 4,
                 initiativeBonus: 2, groupInitiative: true)
        check("a group shares one initiative by default", Set(roll.combatants.compactMap(\.initiative)) == [17])
        roll.clearAll()
        roll.add(name: "Wolf", initiative: 17, armorClass: 13, hp: 11, isPlayer: false, count: 12,
                 initiativeBonus: 2, groupInitiative: false)
        let rolled = roll.combatants.compactMap(\.initiative)
        check("a group can roll for each member", rolled.count == 12 && rolled.allSatisfy { $0 >= 3 && $0 <= 22 }
                  && Set(rolled).count > 1, "\(rolled)")

        // MARK: Health scale
        func level(_ hp: Int?, _ max: Int?, lair: Bool = false) -> Health? {
            var c = Combatant(name: "x", hp: max, isLair: lair)
            c.hp = hp
            return c.health
        }
        check("full HP is healthy", level(20, 20) == .healthy)
        check("above three quarters is still healthy", level(16, 20) == .healthy)
        check("three quarters or fewer is hurt", level(15, 20) == .hurt && level(11, 20) == .hurt)
        check("half or fewer is bloodied", level(10, 20) == .bloodied && level(6, 20) == .bloodied)
        check("a quarter or fewer is critical", level(5, 20) == .critical && level(1, 20) == .critical)
        check("zero is down", level(0, 20) == .down)
        check("no maximum, nothing to scale", level(7, nil) == nil && level(nil, 20) == nil)
        check("lair actions have no health", level(nil, nil, lair: true) == nil)
        check("bloodied agrees with the half-HP line",
              [Int](0...20).allSatisfy { hp in
                  let c = { () -> Combatant in var c = Combatant(name: "x", hp: 20); c.hp = hp; return c }()
                  return c.isBloodied == (hp > 0 && (level(hp, 20) == .bloodied || level(hp, 20) == .critical))
              })

        // MARK: Condition icons
        check("every common condition has its own icon",
              Condition.common.allSatisfy { Condition.symbol(for: $0) != "tag.fill" })
        check("matching ignores case", Condition.symbol(for: "STUNNED") == Condition.symbol(for: "stunned"))
        check("a custom name is matched on a keyword",
              Condition.symbol(for: "On fire") == "flame.fill" && Condition.symbol(for: "Slowed") == "tortoise.fill")
        check("anything else gets the tag", Condition.symbol(for: "Wibbly") == "tag.fill")
        let allSymbols = Set(Condition.common.map { Condition.symbol(for: $0) }
                             + ["On fire", "Exhaustion", "Bleeding", "Slowed", "Frozen", "Dodging", "Asleep",
                                "Bane", "Hexed", "Marked", "Silenced", "Regenerating", "Wibbly"].map {
                                    Condition.symbol(for: $0) })
        let missing = allSymbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        check("every condition icon exists in this macOS", missing.isEmpty, missing.sorted().joined(separator: ", "))

        // MARK: Encounters
        let enc = CombatTracker()
        enc.clearAll()
        enc.add(name: "Mira", initiative: nil, armorClass: 16, hp: 28, isPlayer: true)
        let mira = enc.combatants[0].id
        enc.enterHP(mira, "-10")
        let sceneA = UUID()
        let ambush = enc.addEncounter(name: "  Ambush  ")
        let second = enc.addEncounter(name: "")
        check("an encounter takes a trimmed name, or a numbered one",
              enc.encounters.map(\.name) == ["Ambush", "Encounter 2"], enc.encounters.map(\.name).joined(separator: "|"))
        enc.updateEncounter(ambush) {
            $0.sceneID = sceneA
            $0.monsters = [PlannedMonster(name: "Goblin", count: 3, armorClass: 15, hp: 7, initiativeBonus: 2),
                           PlannedMonster(name: "Boss", armorClass: 17, hp: 21)]
        }
        check("headcount counts every member of a group", enc.encounters[0].headcount == 4)
        var startedWith: [Encounter?] = []
        enc.onStart = { startedWith.append($0) }
        var encEvents: [String] = []
        enc.onEvent = { encEvents.append($0) }

        enc.load(ambush)
        check("loading adds the monsters, numbering a group",
              names(enc.combatants) == "Mira, Goblin 1, Goblin 2, Goblin 3, Boss", names(enc.combatants))
        check("loaded monsters carry their numbers, unrolled",
              enc.combatants.filter { !$0.isPlayer }.allSatisfy { $0.initiative == nil }
                  && enc.combatants.first { $0.name == "Goblin 2" }?.hp == 7
                  && enc.combatants.first { $0.name == "Goblin 2" }?.armorClass == 15
                  && enc.combatants.first { $0.name == "Goblin 2" }?.initiativeBonus == 2)
        check("the party keeps its HP", enc.combatants.first { $0.id == mira }?.hp == 18)
        check("the loaded encounter is the active one", enc.activeEncounter?.name == "Ambush")
        check("loading is logged", encEvents.contains("Encounter: Ambush"), encEvents.joined(separator: "|"))

        enc.update(enc.combatants.first { $0.name == "Goblin 1" }!.id) { $0.hp = 1 }
        enc.load(ambush)
        check("loading again resets the monsters, not the party",
              enc.combatants.first { $0.name == "Goblin 1" }?.hp == 7
                  && enc.combatants.first { $0.id == mira }?.hp == 18 && enc.combatants.count == 5)

        enc.update(mira) { $0.initiative = 12 }
        enc.rollNPCInitiative()
        enc.load(ambush)
        check("before the first turn, loading leaves the party's initiative alone",
              enc.combatants.first { $0.id == mira }?.initiative == 12)

        enc.next()
        check("starting the fight hands the encounter to onStart",
              startedWith.count == 1 && startedWith[0]?.sceneID == sceneA)
        check("the start is logged with the encounter",
              encEvents.contains { $0.hasPrefix("Combat started — Ambush: ") }, encEvents.joined(separator: "|"))
        enc.next()
        check("only the first turn starts the fight", startedWith.count == 1)
        enc.addCondition(mira, name: "Blessed", rounds: nil)

        enc.load(second)
        check("loading mid-fight stops it and clears the party for the next",
              !enc.isRunning && enc.combatants.map(\.name) == ["Mira"]
                  && enc.combatants[0].initiative == nil && enc.combatants[0].conditions.isEmpty
                  && enc.activeEncounter?.name == "Encounter 2")
        enc.undo()
        check("undo reverses a load, fight and all",
              enc.isRunning && enc.activeEncounter?.name == "Ambush" && enc.combatants.count == 5)

        enc.updateEncounter(ambush) { $0.name = "Roadside ambush" }
        enc.undo()
        check("undo leaves what was written into an encounter",
              enc.encounters[0].name == "Roadside ambush" && enc.encounters[0].monsters.count == 2)

        enc.endCombat()
        check("ending marks the encounter done and unloads it",
              enc.encounters[0].done && enc.activeEncounter == nil && !enc.encounters[1].done)
        check("ending logs the encounter",
              encEvents.contains { $0.hasPrefix("Combat ended after ") && $0.hasSuffix("— Roadside ambush") },
              encEvents.joined(separator: "|"))
        enc.undo()
        check("undo reverses ending, the done mark too",
              !enc.encounters[0].done && enc.activeEncounter?.name == "Roadside ambush")

        let reopened = CombatTracker()
        check("encounters persist, with their scene, monsters and active one",
              reopened.encounters.count == 2 && reopened.encounters[0].sceneID == sceneA
                  && reopened.encounters[0].monsters.first?.count == 3
                  && reopened.activeEncounter?.name == "Roadside ambush")

        reopened.removeEncounter(ambush)
        check("deleting the loaded encounter leaves its monsters as ordinary combatants",
              reopened.activeEncounter == nil && reopened.combatants.contains { $0.name == "Boss" }
                  && reopened.encounters.count == 1)
        reopened.clearAll()
        check("clearing the table unloads the encounter", reopened.activeEncounter == nil)

        // MARK: The new fields survive a relaunch
        let persisted = CombatTracker()
        persisted.clearAll()
        persisted.add(name: "Ghoul", initiative: 8, armorClass: 12, hp: 22, isPlayer: false, initiativeBonus: 2)
        let ghoul = persisted.combatants[0].id
        persisted.enterHP(ghoul, "-9")
        persisted.addCondition(ghoul, name: "Poisoned", rounds: 3)
        let again = CombatTracker().combatants.first { $0.id == ghoul }
        check("max HP, bonus and conditions persist",
              again?.hp == 13 && again?.maxHP == 22 && again?.initiativeBonus == 2
                  && again?.conditions.first?.name == "Poisoned" && again?.conditions.first?.rounds == 3)

        // A file from before a field existed still loads.
        let old = #"{"combatants":[{"name":"Old"}],"round":0}"#
        try? old.write(to: Vault.combatFile, atomically: true, encoding: .utf8)
        let loaded = CombatTracker()
        check("a sparse file decodes with defaults",
              loaded.combatants.count == 1 && loaded.combatants[0].initiative == nil
                  && loaded.combatants[0].hp == nil && !loaded.combatants[0].isPlayer)

        // A turn pointing at nobody is repaired on load.
        let id = UUID().uuidString
        let broken = """
        {"combatants":[{"name":"X","initiative":5}],"round":3,"currentID":"\(id)"}
        """
        try? broken.write(to: Vault.combatFile, atomically: true, encoding: .utf8)
        let repaired = CombatTracker()
        check("a dangling turn is repaired on load",
              repaired.current?.name == "X" && repaired.round == 3)

        print(fails == 0 ? "\n  all combat checks pass" : "\n  \(fails) FAILED")
    }
}
