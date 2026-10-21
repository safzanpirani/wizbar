import Foundation

public struct RGB: Equatable, Hashable, Codable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = min(255, max(0, r))
        self.g = min(255, max(0, g))
        self.b = min(255, max(0, b))
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// Relative luminance (sRGB), 0...1. Used to pick legible ink over a swatch.
    public var luminance: Double {
        func channel(_ v: Int) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

public enum LightMode: Equatable, Hashable, Codable, Sendable {
    case white(kelvin: Int)
    case color(RGB)
    case scene(id: Int)
}

public struct BulbState: Equatable, Sendable {
    public var isOn: Bool
    public var brightness: Int
    public var mode: LightMode?
    public var speed: Int?
    public var rssi: Int?
    public var mac: String?

    public init(isOn: Bool, brightness: Int, mode: LightMode?, speed: Int? = nil, rssi: Int? = nil, mac: String? = nil) {
        self.isOn = isOn
        self.brightness = brightness
        self.mode = mode
        self.speed = speed
        self.rssi = rssi
        self.mac = mac
    }

    /// Parses a `getPilot` result. The bulb reports `sceneId` 0 outside scenes,
    /// `temp` in white mode and `r`/`g`/`b` in color mode.
    public init?(pilot: [String: Any]) {
        guard let isOn = pilot["state"] as? Bool else { return nil }
        self.isOn = isOn
        brightness = Brightness.clamp(pilot["dimming"] as? Int ?? 100)
        speed = pilot["speed"] as? Int
        rssi = pilot["rssi"] as? Int
        mac = pilot["mac"] as? String

        if let scene = pilot["sceneId"] as? Int, scene != 0 {
            mode = .scene(id: scene)
        } else if let temp = pilot["temp"] as? Int, temp != 0 {
            mode = .white(kelvin: temp)
        } else if let r = pilot["r"] as? Int, let g = pilot["g"] as? Int, let b = pilot["b"] as? Int {
            mode = .color(RGB(r, g, b))
        } else {
            mode = nil
        }
    }

    public func applying(_ change: PilotChange) -> BulbState {
        var next = self
        if let on = change.on { next.isOn = on }
        if change.on == false { return next }
        if let b = change.brightness { next.brightness = Brightness.clamp(b) }
        if let m = change.mode { next.mode = m }
        if let s = change.speed { next.speed = s }
        return next
    }

    /// The color the light is putting out, for tinting UI.
    public var displayColor: RGB {
        switch mode {
        case .white(let k): return Kelvin.color(k)
        case .color(let c): return c
        case .scene(let id): return Catalog.scene(id)?.colors.first ?? Kelvin.color(2700)
        case nil: return Kelvin.color(2700)
        }
    }
}

public enum Brightness {
    /// The bulb ignores a whole setPilot whose dimming is below 10.
    public static let floor = 10

    public static func clamp(_ value: Int) -> Int { min(100, max(floor, value)) }

    /// Target for a relative change, or nil when nothing should happen. An off
    /// bulb counts as 0, so "brighter" turns it on and "dimmer" leaves it off.
    public static func relative(isOn: Bool, current: Int, delta: Int) -> Int? {
        if !isOn && delta <= 0 { return nil }
        return clamp((isOn ? current : 0) + delta)
    }
}

public enum Speed {
    public static let range = 10...200
    public static func clamp(_ value: Int) -> Int { min(range.upperBound, max(range.lowerBound, value)) }
}

/// One `setPilot` worth of intent. Changes merge so a burst of slider moves
/// collapses into the latest values.
public struct PilotChange: Equatable, Sendable {
    public var on: Bool?
    public var brightness: Int?
    public var mode: LightMode?
    public var speed: Int?

    public init(on: Bool? = nil, brightness: Int? = nil, mode: LightMode? = nil, speed: Int? = nil) {
        self.on = on
        self.brightness = brightness
        self.mode = mode
        self.speed = speed
    }

    public static let off = PilotChange(on: false)

    public mutating func merge(_ newer: PilotChange) {
        if newer.on == false {
            self = newer
            return
        }
        if newer.on == true { on = true }
        if let b = newer.brightness { brightness = b }
        if let m = newer.mode {
            if case .scene = m {} else { speed = nil }
            mode = m
        }
        if let s = newer.speed { speed = s }
    }

    public var params: [String: Any] {
        if on == false { return ["state": false] }
        var p: [String: Any] = ["state": true]
        if let b = brightness { p["dimming"] = Brightness.clamp(b) }
        switch mode {
        case .white(let k): p["temp"] = Kelvin.clamp(k)
        case .color(let c): p["r"] = c.r; p["g"] = c.g; p["b"] = c.b
        case .scene(let id): p["sceneId"] = id
        case nil: break
        }
        if let s = speed { p["speed"] = Speed.clamp(s) }
        return p
    }
}

public enum Kelvin {
    public static let range = 2200...6500

    public static func clamp(_ k: Int) -> Int { min(range.upperBound, max(range.lowerBound, k)) }

    /// Approximate sRGB for a blackbody temperature (Tanner Helland's fit).
    public static func color(_ kelvin: Int) -> RGB {
        let t = Double(clamp(kelvin)) / 100
        let r: Double = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g: Double = t <= 66
            ? 99.4708025861 * log(t) - 161.1195681661
            : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b: Double = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        return RGB(Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
    }
}
