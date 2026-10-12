import CoreGraphics
import Foundation

let usage = """
usage: screenski <command> [options]

commands:
  displays                     List displays: ID, name, resolution, DDC support
  virtual [options]            Create a virtual display and show it on your monitor, scaled down.
                               Runs until Ctrl-C.
      --size WxH               Pixel size of the virtual display (default 3840x2160)
      --lodpi                  Use every pixel as workspace (tiny UI) instead of 2x HiDPI
      --refresh HZ             Refresh rate (default 60)
      --onto DISPLAY           Monitor that shows the virtual display (default: main display)
      --no-mirror              Only add the virtual display; don't change your monitor
      --for SECONDS            Stop automatically after SECONDS
  brightness [VALUE]           Show brightness, or set it: 0-100, +N, -N, up, down
      --display DISPLAY        Monitor to control (default: first one with DDC)
      --verbose                Print the raw DDC reply

DISPLAY is a display ID or part of a display name, as shown by `screenski displays`.
"""

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Minimal argument parsing: options are pulled out by name, positionals are taken in order.
struct Arguments {
    private var items: [String]

    init(_ items: [String]) { self.items = items }

    mutating func flag(_ name: String) -> Bool {
        guard let index = items.firstIndex(of: name) else { return false }
        items.remove(at: index)
        return true
    }

    mutating func option(_ name: String) throws -> String? {
        guard let index = items.firstIndex(of: name) else { return nil }
        guard index + 1 < items.count else { throw CLIError("\(name) needs a value") }
        let value = items[index + 1]
        items.removeSubrange(index...index + 1)
        return value
    }

    mutating func next() -> String? {
        items.isEmpty ? nil : items.removeFirst()
    }

    func finish() throws {
        if let extra = items.first { throw CLIError("unexpected argument \"\(extra)\"") }
    }
}

func virtualDisplay(_ args: inout Arguments) throws -> Never {
    var options = VirtualSession.Options()
    if let size = try args.option("--size") {
        let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ $0 > 0 && $0 % 2 == 0 }) else {
            throw CLIError("--size must look like 3840x2160 (even numbers)")
        }
        (options.pixelWidth, options.pixelHeight) = (parts[0], parts[1])
    }
    if let refresh = try args.option("--refresh") {
        guard let hz = Double(refresh), hz > 0 else { throw CLIError("--refresh must be a number of Hz") }
        options.refreshRate = hz
    }
    if let seconds = try args.option("--for") {
        guard let duration = TimeInterval(seconds), duration > 0 else { throw CLIError("--for must be a number of seconds") }
        options.duration = duration
    }
    options.hiDPI = !args.flag("--lodpi")
    let onto = try args.option("--onto")
    let noMirror = args.flag("--no-mirror")
    try args.finish()

    if !noMirror {
        options.mirrorTarget = try onto.map(Display.find) ?? Display(id: CGMainDisplayID())
    }
    try VirtualSession(options: options).run()
}

var args = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    switch args.next() {
    case "displays":
        try args.finish()
        listDisplays()
    case "virtual":
        try virtualDisplay(&args)
    case "brightness":
        try brightness(&args)
    case nil, "help", "-h", "--help":
        print(usage)
    case let command?:
        throw CLIError("unknown command \"\(command)\"\n\n\(usage)")
    }
} catch {
    FileHandle.standardError.write(Data("screenski: \(error)\n".utf8))
    exit(1)
}
