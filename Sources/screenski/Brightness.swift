import Foundation
import CPrivateDisplay

private let luminanceVCP: UInt8 = 0x10
private let defaultStep = 10

/// `screenski brightness [VALUE]`, via DDC/CI. Values are percentages.
///
/// Many monitors accept DDC writes but never answer reads, so the last value screenski set is
/// remembered per monitor and used as the starting point for relative changes.
func brightness(_ args: inout Arguments) throws {
    let display = try args.option("--display").map(Display.find) ?? defaultDDCDisplay()
    let verbose = args.flag("--verbose")
    let request = args.next()
    try args.finish()

    let reading = readBrightness(display, verbose: verbose)
    let remembered = UserDefaults.screenski.object(forKey: rememberedKey(display)) as? Int

    guard let request else {
        if let reading {
            print("\(display.name): \(reading.percent)")
        } else if let remembered {
            print("\(display.name): \(remembered) (last value set by screenski; the monitor doesn't report brightness)")
        } else {
            throw CLIError("\(display.name) doesn't report its brightness. Set it once, e.g. `screenski brightness 50`.")
        }
        return
    }

    let target: Int
    if let delta = relativeChange(request) {
        guard let current = reading?.percent ?? remembered else {
            throw CLIError("\(display.name) doesn't report its brightness, so there's nothing to adjust from. Set it once, e.g. `screenski brightness 50`.")
        }
        target = current + delta
    } else if let absolute = Int(request) {
        target = absolute
    } else {
        throw CLIError("brightness must be 0-100, +N, -N, up or down (got \"\(request)\")")
    }

    let percent = min(max(target, 0), 100)
    let maximum = reading?.maximum ?? 100
    let result = SKDDCWrite(display.id, luminanceVCP, UInt16(percent * maximum / 100))
    guard result == kIOReturnSuccess else {
        throw CLIError("DDC write to \(display.name) failed (\(hex(result)))")
    }
    UserDefaults.screenski.set(percent, forKey: rememberedKey(display))
    print("\(display.name): \(percent)")
}

private func relativeChange(_ request: String) -> Int? {
    switch request {
    case "up": return defaultStep
    case "down": return -defaultStep
    default:
        guard request.hasPrefix("+") || request.hasPrefix("-") else { return nil }
        return Int(request)
    }
}

private func readBrightness(_ display: Display, verbose: Bool) -> (percent: Int, maximum: Int)? {
    var current: UInt16 = 0
    var maximum: UInt16 = 0
    var reply = [UInt8](repeating: 0, count: 12)
    let result = SKDDCRead(display.id, luminanceVCP, &current, &maximum, &reply)
    if verbose {
        let bytes = reply.map { String(format: "%02x", $0) }.joined(separator: " ")
        FileHandle.standardError.write(Data("DDC read: \(hex(result)), current \(current), max \(maximum), reply [\(bytes)]\n".utf8))
    }
    guard result == kIOReturnSuccess, maximum > 0 else { return nil }
    return (Int(current) * 100 / Int(maximum), Int(maximum))
}

private func defaultDDCDisplay() throws -> Display {
    guard let display = Display.online().first(where: \.supportsDDC) else {
        throw CLIError("no external display with DDC found")
    }
    return display
}

private func rememberedKey(_ display: Display) -> String {
    "brightness.\(display.persistentKey)"
}

private func hex(_ result: IOReturn) -> String {
    String(format: "0x%08x", UInt32(bitPattern: result))
}

extension UserDefaults {
    static let screenski = UserDefaults(suiteName: "screenski") ?? .standard
}
