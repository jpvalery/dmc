import AppKit
let candidates = [
 "cloud.rain","cloud.heavyrain","cloud.bolt.rain","cloud.fog","cloud.sun","wind","wind.snow",
 "snowflake","sun.max","sun.haze","moon.stars","moon","tornado","drop","flame","leaf","tree",
 "mountain.2","water.waves","humidity","hurricane","sparkles","bolt","rainbow",
 "building.columns","building.2","house","tent","door.left.hand.open","stairs","bed.double",
 "fork.knife","cup.and.saucer","books.vertical","theatermasks","storefront","lightbulb","candle",
 "shield","shield.lefthalf.filled","hammer","target","crown","figure.fencing","flag","trophy",
 "pawprint","ant","bird","hare","tortoise","fish","lizard","ladybug","spider","carrot",
 "wand.and.stars","eye","hexagon","atom","circle.hexagongrid","seal","scroll","book.closed",
 "waveform","music.note","music.quarternote.3","bell","megaphone","speaker.wave.3","ear",
 "sailboat","ferry","car","airplane","map","signpost.right","road.lanes","train.side.front.car",
 "gear","key","lock","hourglass","clock","dice","die.face.5","suit.club","suit.spade",
 "cross.case","bandage","pills","testtube.2","cauldron","anvil","pickaxe","fossil.shell",
 "sparkle","moonphase.waxing.crescent","globe.europe.africa","compass.drawing","binoculars",
 "figure.walk","person.3","crown.fill","swords","gearshape","wrench.adjustable","chevron.up",
]
var ok: [String] = [], bad: [String] = []
for c in candidates {
    if NSImage(systemSymbolName: c, accessibilityDescription: nil) != nil { ok.append(c) } else { bad.append(c) }
}
print("VALID (\(ok.count)):")
print(ok.map { "\"\($0)\"" }.joined(separator: ", "))
print("\nINVALID (\(bad.count)): \(bad.joined(separator: ", "))")
