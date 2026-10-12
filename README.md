# screenski

A small macOS CLI for two things:

1. **A 4K virtual display for recording.** `screenski virtual` creates a 3840×2160 virtual display (HiDPI, so the UI looks like 1920×1080) and mirrors your monitor onto it. macOS renders everything at 4K and scales it down to your 1080p monitor; OBS records the virtual display at full 4K.
2. **Monitor brightness from the command line**, over DDC/CI.

Requires an Apple Silicon Mac. Uses private macOS APIs (`CGVirtualDisplay`, `IOAVService`), the same ones DeskPad, BetterDisplay and m1ddc use.

## Install

```bash
brew install lookevink/tap/screenski
```

Homebrew builds it from source, which needs the Xcode Command Line Tools (`xcode-select --install`).

Or build it yourself:

```bash
swift build -c release
cp .build/release/screenski /opt/homebrew/bin/   # or anywhere on your PATH
```

## Usage

```bash
screenski displays                 # IDs, names, resolutions, DDC support
screenski virtual                  # 4K HiDPI virtual display, mirrored onto the main monitor; Ctrl-C to stop
screenski virtual --lodpi          # 3840×2160 of workspace at 1x (tiny UI on a 1080p monitor)
screenski virtual --no-mirror      # just add the display next to your monitor
screenski virtual --for 15         # stop automatically (handy for testing)
screenski brightness               # current brightness
screenski brightness 60            # set (0-100)
screenski brightness +10           # or -10, up, down
```

The virtual display only exists while `screenski virtual` runs. When it exits, for any reason, macOS removes it and your monitor goes back to normal.

### Recording in OBS

Add a **macOS Screen Capture** source, set the method to **Display Capture**, and pick the `screenski 3840x2160` display. In **Settings → Video**, set Base and Output resolution to 3840×2160.

### Brightness on monitors that don't report it

Some monitors and HDMI adapters accept DDC writes but never answer reads. screenski then remembers the last brightness it set for each monitor, so `+10` / `-10` keep working after you set an absolute value once. `screenski brightness --verbose` prints the raw DDC reply.

## Credits

The DDC code follows [m1ddc](https://github.com/waydabber/m1ddc) (MIT). [DeskPad](https://github.com/Stengo/DeskPad) showed the way for the `CGVirtualDisplay` API.

## License

MIT
