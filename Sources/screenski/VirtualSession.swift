import Foundation
import CPrivateDisplay

/// Keeps a virtual display alive for the life of the process and, optionally, mirrors a physical
/// display onto it. macOS removes the virtual display (and so the mirroring) when the process exits.
final class VirtualSession {
    struct Options {
        var pixelWidth = 3840
        var pixelHeight = 2160
        var refreshRate = 60.0
        /// Render at 2x, so the UI looks like pixelWidth/2 x pixelHeight/2.
        var hiDPI = true
        /// Physical display that will show the virtual one, scaled down. nil = just add the display.
        var mirrorTarget: Display?
        var duration: TimeInterval?
    }

    private let options: Options
    private var display: CGVirtualDisplay?
    private var signalSources: [DispatchSourceSignal] = []

    init(options: Options) {
        self.options = options
    }

    private var pointWidth: Int { options.hiDPI ? options.pixelWidth / 2 : options.pixelWidth }
    private var pointHeight: Int { options.hiDPI ? options.pixelHeight / 2 : options.pixelHeight }

    /// Creates the display and never returns; Ctrl-C (or --for) cleans up and exits.
    func run() throws -> Never {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = "screenski \(options.pixelWidth)x\(options.pixelHeight)"
        descriptor.maxPixelsWide = UInt32(options.pixelWidth)
        descriptor.maxPixelsHigh = UInt32(options.pixelHeight)
        // Physical size only feeds macOS's DPI heuristics; ~27" keeps them sensible.
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 600 * Double(options.pixelHeight) / Double(options.pixelWidth))
        descriptor.vendorID = 0x5353
        descriptor.productID = 0x0001
        descriptor.serialNum = 0x0001
        descriptor.terminationHandler = { [weak self] _, _ in self?.stop(status: 1, message: "macOS removed the virtual display") }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            throw CLIError("macOS refused to create a virtual display")
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = options.hiDPI ? 1 : 0
        // Offer both the full and half size: depending on the macOS version, HiDPI modes are
        // derived from one or the other. configure() then picks the exact mode we want.
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(options.pixelWidth), height: UInt(options.pixelHeight), refreshRate: options.refreshRate),
            CGVirtualDisplayMode(width: UInt(options.pixelWidth / 2), height: UInt(options.pixelHeight / 2), refreshRate: options.refreshRate),
        ]
        guard display.apply(settings) else {
            throw CLIError("macOS rejected the virtual display settings")
        }
        self.display = display

        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in self?.stop(status: 0, message: nil) }
            source.resume()
            signalSources.append(source)
        }
        if let duration = options.duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.stop(status: 0, message: "Stopping after \(Int(duration))s.")
            }
        }

        DispatchQueue.main.async { self.configure(attempt: 0) }
        dispatchMain()
    }

    /// The new display takes a moment to come online, so retry until our mode shows up.
    private func configure(attempt: Int) {
        guard let display else { return }
        let modes = CGDisplayCopyAllDisplayModes(display.displayID, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        let wanted = modes.first {
            $0.width == pointWidth && $0.height == pointHeight && $0.pixelWidth == options.pixelWidth && $0.pixelHeight == options.pixelHeight
        }
        guard let mode = wanted else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.configure(attempt: attempt + 1) }
            } else {
                let offered = modes.map(\.summary).joined(separator: "\n  ")
                stop(status: 1, message: "the virtual display never offered \(pointWidth)x\(pointHeight) at \(options.pixelWidth)x\(options.pixelHeight) px. Offered:\n  \(offered)")
            }
            return
        }

        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayWithDisplayMode(config, display.displayID, mode, nil)
        if let target = options.mirrorTarget {
            CGConfigureDisplayMirrorOfDisplay(config, target.id, display.displayID)
        }
        let error = CGCompleteDisplayConfiguration(config, .forSession)
        guard error == .success else {
            stop(status: 1, message: "couldn't configure the displays (CGError \(error.rawValue))")
            return
        }

        let name = Display(id: display.displayID).name
        print("Virtual display \"\(name)\" (ID \(display.displayID)): \(mode.summary)")
        if let target = options.mirrorTarget {
            print("\(target.name) (ID \(target.id)) now shows it, scaled to fit.")
        }
        print("In OBS, add a macOS Screen Capture source and pick \"\(name)\". Press Ctrl-C to stop.")
    }

    private func stop(status: Int32, message: String?) {
        if let message { print(message) }
        if let display, let target = options.mirrorTarget, CGDisplayMirrorsDisplay(target.id) == display.displayID {
            var config: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&config)
            CGConfigureDisplayMirrorOfDisplay(config, target.id, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
        display = nil
        exit(status)
    }
}
