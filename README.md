# WizBar

A macOS menu bar app for one Philips WiZ bulb. It talks to the bulb directly over the local UDP protocol (port 38899) and needs no cloud account.

Requires macOS 14 or later on Apple silicon.

## Using it

| Action | Result |
|---|---|
| Click the bulb icon | Opens the panel |
| Option-click the icon | Switches the light on or off |
| Right-click the icon | Menu with on/off, favorites, settings and quit |
| Scroll over the icon | Changes brightness; the level shows next to the icon for a moment |
| ⌃⌥⌘L, ⌃⌥⌘=, ⌃⌥⌘- | On/off, brighter, dimmer, from any app (can be turned off in settings) |

The panel has a power button, a brightness slider and three tabs:

- **White**: a temperature slider from 2200K to 6500K and seven presets, from Candle to Daylight.
- **Color**: 23 named colors, plus hue and saturation sliders.
- **Scenes**: the WiZ scenes in groups, with a speed slider for animated ones. Rhythm is left out because it needs the phone's microphone.

Favorites save the current mode and brightness. Right-click a favorite to reorder or remove it. Up to eight are kept.

Keys inside the panel: Space switches the light, the arrow keys change brightness by 5, 1/2/3 pick a tab, ⌘, opens settings.

Settings hold the bulb's name and IP address, a Test button that reads the bulb's module and firmware, a switch to keep the brightness next to the icon, the global shortcut switch, and Open at login. The WiZ app shows the bulb's IP address in the light's settings, and your router lists it too.

## Build and install

```sh
scripts/build.sh            # builds build/WizBar.app
scripts/build.sh --install  # also replaces ~/Applications/WizBar.app and relaunches it
scripts/test.sh             # unit tests for WizKit
swift scripts/make-icon.swift  # regenerates Resources/AppIcon.icns
```

The build works with only the Command Line Tools installed. Two workarounds make that possible:

- SwiftUI's `@State` is a macro whose plugin ships only with Xcode. The views use `@ViewState`, a typealias for the `SwiftUI.State` property wrapper (`Sources/WizBar/Views/Theme.swift`).
- swift-testing's macro plugin and runtime libraries are not on the default search paths. `scripts/test.sh` passes them in.

The app is signed ad hoc. macOS asks for Local Network access the first time WizBar contacts the bulb. A rebuild changes the signature, so macOS may ask again after an update.

## Layout

- `Sources/WizKit`: the protocol. `WizClient` sends each request up to three times, 150 ms apart, and takes the first reply whose `method` matches. `Model.swift` parses `getPilot` and builds `setPilot` parameters. `Catalog.swift` holds scenes, colors and white presets.
- `Sources/WizBar`: the app. `LightStore` holds the bulb state, applies changes to the UI straight away, and merges slider moves so a drag sends one request per round trip. `StatusItemController` owns the menu bar icon, panel, menu and scroll handling.

## Bulb behavior worth knowing

- Firmware 1.35 (`ESP01_SHRGB1C_31`) fills the `src` field of every reply with a few bytes of uninitialized memory. Those bytes are often invalid UTF-8, and a strict JSON parser rejects the whole reply. `WizClient.parseReply` cuts the field out before parsing. Before that fix, about one status read in four failed during bursts and the panel kept saying it had lost contact.
- The bulb ignores an entire `setPilot` whose `dimming` is below 10, so brightness is clamped to 10-100.
- A reply usually takes about 12 ms on the home Wi-Fi.
- The panel polls every 2.5 s while open and every 30 s while closed. The panel reports the bulb as lost after two failed reads in a row or one failed command.
