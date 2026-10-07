import SwiftUI

/// A curated icon set for scenes. Every name here was validated against the installed SF Symbols
/// catalogue, so none render as a blank slot.
enum SceneSymbols {
    static let all: [String] = [
        "cloud.rain", "cloud.heavyrain", "cloud.bolt.rain", "cloud.fog", "cloud.sun", "wind",
        "wind.snow", "snowflake", "sun.max", "sun.haze", "moon.stars", "moon", "tornado", "drop",
        "flame", "leaf", "tree", "mountain.2", "water.waves", "humidity", "hurricane", "sparkles",
        "bolt", "rainbow", "moonphase.waxing.crescent",
        "building.columns", "building.2", "house", "tent", "door.left.hand.open", "stairs",
        "bed.double", "fork.knife", "cup.and.saucer", "books.vertical", "theatermasks",
        "storefront", "lightbulb",
        "shield", "shield.lefthalf.filled", "hammer", "target", "crown", "figure.fencing", "flag",
        "trophy", "cross.case", "bandage", "pills", "testtube.2",
        "pawprint", "ant", "bird", "hare", "tortoise", "fish", "lizard", "ladybug", "carrot",
        "fossil.shell",
        "wand.and.stars", "eye", "hexagon", "atom", "circle.hexagongrid", "seal", "scroll",
        "book.closed", "sparkle",
        "waveform", "music.note", "music.quarternote.3", "bell", "megaphone", "speaker.wave.3",
        "ear",
        "sailboat", "ferry", "car", "airplane", "map", "signpost.right", "road.lanes",
        "train.side.front.car", "compass.drawing", "binoculars", "globe.europe.africa",
        "gear", "key", "lock", "hourglass", "clock", "dice", "die.face.5", "suit.club",
        "suit.spade", "figure.walk", "person.3",
    ]
}

struct SymbolPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [String] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return SceneSymbols.all }
        return SceneSymbols.all.filter { $0.contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose an icon").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)

            TextField("Filter icons", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 8),
                          spacing: 6) {
                    ForEach(matches, id: \.self) { symbol in
                        Button {
                            selection = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(selection == symbol ? Color.accentColor.opacity(0.25) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 430, height: 420)
    }
}
