import AppKit
import CPrivateDisplay

/// An online display, physical or virtual.
struct Display {
    let id: CGDirectDisplayID

    static func online() -> [Display] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map(Display.init)
    }

    /// Finds a display by ID or by part of its name.
    static func find(_ query: String) throws -> Display {
        let displays = online()
        if let id = UInt32(query), let match = displays.first(where: { $0.id == id }) {
            return match
        }
        let matches = displays.filter { $0.name.localizedCaseInsensitiveContains(query) }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw CLIError("no display matches \"\(query)\" (see `screenski displays`)")
        default: throw CLIError("\"\(query)\" matches several displays; use its ID")
        }
    }

    var name: String {
        if let info = CoreDisplay_DisplayCreateInfoDictionary(id) as? [String: Any],
           let names = info["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.values.first {
            return name
        }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "Display \(id)"
    }

    var mode: CGDisplayMode? { CGDisplayCopyDisplayMode(id) }
    var isMain: Bool { CGDisplayIsMain(id) != 0 }

    /// The display this one is mirroring, if any.
    var mirrorSource: CGDirectDisplayID? {
        let source = CGDisplayMirrorsDisplay(id)
        return source == kCGNullDirectDisplay ? nil : source
    }

    var supportsDDC: Bool { SKDDCIsAvailable(id) }

    /// Stable across reboots, unlike the display ID; used to remember per-monitor state.
    var persistentKey: String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}

extension CGDisplayMode {
    /// e.g. "1920x1080 (3840x2160 px) @ 60Hz"
    var summary: String {
        let pixels = pixelWidth == width ? "" : " (\(pixelWidth)x\(pixelHeight) px)"
        return "\(width)x\(height)\(pixels) @ \(Int(refreshRate.rounded()))Hz"
    }
}

func listDisplays() {
    for display in Display.online() {
        var notes: [String] = []
        if display.isMain { notes.append("main") }
        if let source = display.mirrorSource { notes.append("mirroring \(source)") }
        if display.supportsDDC { notes.append("DDC") }
        let mode = display.mode?.summary ?? "inactive"
        print("\(String(display.id).padding(8))\(display.name.padding(24))\(mode.padding(36))\(notes.joined(separator: ", "))")
    }
}

private extension String {
    func padding(_ width: Int) -> String {
        count >= width ? self + " " : padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
