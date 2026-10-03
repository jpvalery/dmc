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
