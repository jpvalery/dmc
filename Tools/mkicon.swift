import AppKit
import CoreGraphics
import Foundation

// Apple's icon grid: on a 1024pt canvas the artwork body is 824pt, centred, with continuous
// (superelliptical) corners — not a plain rounded rect. Getting this right is the difference
// between an icon that sits correctly in the Dock and one that reads as a square sticker.
let canvas: CGFloat = 1024
let body: CGFloat = 824
let inset = (canvas - body) / 2

func superellipse(in rect: CGRect, n: CGFloat = 5, samples: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    for i in 0...samples {
        let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

let srcURL = URL(filePath: CommandLine.arguments[1])
let outDir = URL(filePath: CommandLine.arguments[2])

guard let srcData = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
      let source = CGImageSourceCreateImageAtIndex(srcData, 0, nil) else {
    fatalError("could not read \(srcURL.path)")
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let bodyRect = CGRect(x: inset, y: inset, width: body, height: body)

// Soft contact shadow, the way system icons sit on the Dock.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18,
              color: NSColor.black.withAlphaComponent(0.28).cgColor)
ctx.addPath(superellipse(in: bodyRect))
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(superellipse(in: bodyRect))
ctx.clip()
ctx.draw(source, in: bodyRect)
ctx.restoreGState()

guard let master = ctx.makeImage() else { fatalError("no image") }

// Every size macOS asks for, at both scales.
let specs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for spec in specs {
    guard let c = CGContext(data: nil, width: spec.px, height: spec.px,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    c.interpolationQuality = .high
    c.clear(CGRect(x: 0, y: 0, width: spec.px, height: spec.px))
    c.draw(master, in: CGRect(x: 0, y: 0, width: spec.px, height: spec.px))
    guard let img = c.makeImage() else { continue }
    let url = outDir.appending(path: "\(spec.name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("  \(spec.name).png  \(spec.px)x\(spec.px)")
}
print("iconset written")
