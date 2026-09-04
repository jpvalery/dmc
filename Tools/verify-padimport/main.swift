import Foundation
let text = try String(contentsOf: URL(filePath: CommandLine.arguments[1]), encoding: .utf8)
guard let r = PadImport.parse(text) else { print("FAIL: did not parse"); exit(1) }
print("slots: \(r.slots.count) | looping: \(r.looping) | one-shot: \(r.oneShots) | skipped: \(r.skipped)")
let scene = PadImport.scene(named: "Imported pad", from: r)
print("scene layers: \(scene.layers.count), all unbound: \(scene.layers.allSatisfy { !$0.isBound })")
print("gain range: \(scene.layers.map(\.gain).min()!) … \(scene.layers.map(\.gain).max()!)")
print("first 5 slots:")
for l in scene.layers.prefix(5) {
    print("  pad \(l.padID ?? "?")  gain \(String(format: "%.2f", l.gain))  \(l.loops ? "loop" : "one-shot")")
}
// Round-trips through scenes.json unchanged?
let data = try JSONEncoder().encode([scene])
let back = try JSONDecoder().decode([SoundScene].self, from: data)
print("round-trip ok: \(back[0].layers.count == scene.layers.count && back[0].layers[3].padID == scene.layers[3].padID && back[0].layers[3].gain == scene.layers[3].gain)")
