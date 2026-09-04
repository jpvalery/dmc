import Foundation
import IOKit.hid

@main
struct SetMap {
    static var inbox: [[UInt8]] = []

    // Grid is matrix row 0. Cols 0-4 top row, 5-9 middle, 10-14 bottom.
    // Encoder presses: col 17 = left, 15 = centre, 16 = right.
    static let keys: [(col: UInt8, code: UInt16, name: String)] = [
        (0,  0x0068, "F13"),        (1,  0x0069, "F14"),        (2,  0x006A, "F15"),
        (3,  0x006B, "F16"),        (4,  0x0009, "F"),
        (5,  0x0268, "LSFT(F13)"),  (6,  0x0269, "LSFT(F14)"),  (7,  0x026A, "LSFT(F15)"),
        (8,  0x026B, "LSFT(F16)"),  (9,  0x0015, "R"),
        (10, 0x0168, "LCTL(F13)"),  (11, 0x0169, "LCTL(F14)"),  (12, 0x016A, "LCTL(F15)"),
        (13, 0x016B, "LCTL(F16)"),  (14, 0x001B, "X"),
        (17, 0x046A, "press L: DMC mute  LALT(F15)"),
        (15, 0x00D3, "press C: middle-click"),
        (16, 0x7843, "press R: RGB mode next"),
    ]

    // (encoder index, ccw, cw)
    static let encoders: [(idx: UInt8, ccw: UInt16, cw: UInt16, name: String)] = [
        (0, 0x0469, 0x0468, "left   DMC volume  LALT(F14/F13)"),
        (1, 0x00DA, 0x00D9, "centre wheel down/up"),
        (2, 0x784A, 0x7849, "right  RGB brightness"),
    ]

    static func main() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0xF1F1] as CFDictionary)
        IOHIDManagerOpen(mgr, 0)
        guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
              let dev = set.first(where: {
                  (IOHIDDeviceGetProperty($0, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue == 0xFF60
              }), IOHIDDeviceOpen(dev, 0) == kIOReturnSuccess else { print("no raw-HID device"); return }
        var buf = [UInt8](repeating: 0, count: 32)
        IOHIDDeviceRegisterInputReportCallback(dev, &buf, 32, { _,_,_,_,_, r, l in
            SetMap.inbox.append(Array(UnsafeBufferPointer(start: r, count: min(Int(l), 32))))
        }, nil)
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        func cmd(_ p: [UInt8]) -> [UInt8]? {
            inbox.removeAll()
            var o = [UInt8](repeating: 0, count: 32)
            for (i,b) in p.enumerated() { o[i] = b }
            guard IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, o, 32) == kIOReturnSuccess else { return nil }
            let end = Date().addingTimeInterval(0.6)
            var m: [UInt8]?
            while m == nil && Date() < end {
                CFRunLoopRunInMode(.defaultMode, 0.02, true)
                m = inbox.first { $0.count > 1 && $0[0] == p[0] }
            }
            usleep(30_000)
            return m
        }

        print("=== writing keys (layer 0) ===")
        var ok = 0, bad = 0
        for k in keys {
            _ = cmd([0x05, 0, 0, k.col, UInt8(k.code >> 8), UInt8(k.code & 0xFF)])
            let back = cmd([0x04, 0, 0, k.col])
            let got = back.map { UInt16($0[4]) << 8 | UInt16($0[5]) } ?? 0
            let good = got == k.code
            good ? (ok += 1) : (bad += 1)
            print(String(format: "  col %2d  %-22s 0x%04X  %@", Int(k.col),
                         (k.name as NSString).utf8String!, got, good ? "ok" : "MISMATCH"))
        }
        print("=== writing encoders (layer 0) ===")
        for e in encoders {
            _ = cmd([0x15, 0, e.idx, 0, UInt8(e.ccw >> 8), UInt8(e.ccw & 0xFF)])
            _ = cmd([0x15, 0, e.idx, 1, UInt8(e.cw  >> 8), UInt8(e.cw  & 0xFF)])
            let b0 = cmd([0x14, 0, e.idx, 0]).map { UInt16($0[4]) << 8 | UInt16($0[5]) } ?? 0
            let b1 = cmd([0x14, 0, e.idx, 1]).map { UInt16($0[4]) << 8 | UInt16($0[5]) } ?? 0
            let good = b0 == e.ccw && b1 == e.cw
            good ? (ok += 1) : (bad += 1)
            print(String(format: "  enc %d   %-26s ccw 0x%04X cw 0x%04X  %@", Int(e.idx),
                         (e.name as NSString).utf8String!, b0, b1, good ? "ok" : "MISMATCH"))
        }
        print("\n  \(ok) written and verified, \(bad) mismatched")
        IOHIDDeviceClose(dev, 0)
    }
}
