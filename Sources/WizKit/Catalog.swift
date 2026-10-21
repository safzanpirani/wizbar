import Foundation

public struct LightScene: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let symbol: String
    public let colors: [RGB]
    /// Animated scenes accept a `speed` (10-200).
    public let animated: Bool
}

public struct SceneGroup: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let scenes: [LightScene]
}

public struct NamedColor: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let rgb: RGB
}

public struct WhitePreset: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let kelvin: Int
}

public enum Catalog {
    private static func hex(_ value: UInt32) -> RGB {
        RGB(Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }

    private static func s(_ id: Int, _ name: String, _ symbol: String, _ a: UInt32, _ b: UInt32, animated: Bool) -> LightScene {
        LightScene(id: id, name: name, symbol: symbol, colors: [hex(a), hex(b)], animated: animated)
    }

    /// WiZ scene ids, grouped the way people pick them. Rhythm (1000) needs the
    /// phone's microphone, so it is left out.
    public static let sceneGroups: [SceneGroup] = [
        SceneGroup(title: "Everyday", scenes: [
            s(6, "Cozy", "cup.and.saucer.fill", 0xFF9A3C, 0xFFCC80, animated: true),
            s(16, "Relax", "leaf.fill", 0xFFCF99, 0xFFB066, animated: false),
            s(15, "Focus", "scope", 0xF0F6FF, 0xA8C8FF, animated: false),
            s(18, "TV time", "tv.fill", 0x7B6CFF, 0x3F37C9, animated: false),
            s(14, "Night light", "moon.stars.fill", 0xFF9E40, 0x8C4A1A, animated: false),
            s(29, "Candlelight", "flame", 0xFFB347, 0xFF8C00, animated: true),
            s(10, "Bedtime", "bed.double.fill", 0xF4A261, 0xB5562F, animated: true),
            s(9, "Wake-up", "alarm.fill", 0xFFD166, 0xFFF3B0, animated: true),
            s(17, "True colors", "eye.fill", 0xFFF4E0, 0xFFE0B0, animated: false),
        ]),
        SceneGroup(title: "Whites", scenes: [
            s(11, "Warm white", "sun.min.fill", 0xFFD8A8, 0xFFB870, animated: false),
            s(30, "Golden white", "sun.haze.fill", 0xFFE5A0, 0xFFC94D, animated: true),
            s(34, "White", "circle.fill", 0xFFFFFF, 0xF2EDE4, animated: false),
            s(12, "Daylight", "sun.max.fill", 0xFFF7E0, 0xFFE8A3, animated: false),
            s(13, "Cool white", "snowflake", 0xE0F0FF, 0xB8D8FF, animated: false),
        ]),
        SceneGroup(title: "Moving", scenes: [
            s(5, "Fireplace", "flame.fill", 0xFF4500, 0xFFA500, animated: true),
            s(3, "Sunset", "sun.horizon.fill", 0xFF7E5F, 0xFEB47B, animated: true),
            s(1, "Ocean", "water.waves", 0x0077BE, 0x00C2C7, animated: true),
            s(7, "Forest", "tree.fill", 0x2D6A4F, 0x95D5B2, animated: true),
            s(2, "Romance", "heart.fill", 0xFF4D6D, 0xC9184A, animated: true),
            s(8, "Pastel colors", "paintpalette.fill", 0xFFC8DD, 0xBDE0FE, animated: true),
            s(23, "Deep dive", "fish.fill", 0x03045E, 0x0096C7, animated: true),
            s(24, "Jungle", "bird.fill", 0x007F5F, 0xAACC00, animated: true),
            s(25, "Mojito", "wineglass.fill", 0x80ED99, 0xC7F9CC, animated: true),
            s(32, "Steampunk", "gearshape.2.fill", 0xB5651D, 0xFFB347, animated: true),
            s(19, "Plantgrowth", "camera.macro", 0xD000FF, 0xFF2E63, animated: false),
        ]),
        SceneGroup(title: "Party", scenes: [
            s(4, "Party", "party.popper.fill", 0xFF00CC, 0x3333FF, animated: true),
            s(26, "Club", "music.note", 0x7209B7, 0xF72585, animated: true),
            s(31, "Pulse", "waveform.path.ecg", 0xFF006E, 0x8338EC, animated: true),
            s(35, "Alarm", "bell.fill", 0xFF0000, 0xFF6B6B, animated: true),
        ]),
        SceneGroup(title: "Seasons", scenes: [
            s(33, "Diwali", "sparkles", 0xFF9933, 0xFFD700, animated: true),
            s(27, "Christmas", "gift.fill", 0xD62828, 0x2A9D8F, animated: true),
            s(28, "Halloween", "theatermasks.fill", 0xFF7518, 0x6A0DAD, animated: true),
            s(20, "Spring", "camera.macro.circle.fill", 0xA8E063, 0xFFD6E8, animated: true),
            s(21, "Summer", "beach.umbrella.fill", 0xFFBE0B, 0xFB5607, animated: true),
            s(22, "Fall", "wind", 0xD4A373, 0xBC6C25, animated: true),
            s(36, "Snowy sky", "cloud.snow.fill", 0xDBE9F6, 0x9FC5E8, animated: true),
        ]),
    ]

    public static let scenes: [LightScene] = sceneGroups.flatMap(\.scenes)

    private static let scenesById: [Int: LightScene] = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0) })

    public static func scene(_ id: Int) -> LightScene? { scenesById[id] }

    public static let colors: [NamedColor] = [
        ("Red", 0xFF0000), ("Crimson", 0xDC143C), ("Coral", 0xFF7F50), ("Orange", 0xFF8C00),
        ("Amber", 0xFFBF00), ("Gold", 0xFFD700), ("Yellow", 0xFFFF00), ("Peach", 0xFFDAB9),
        ("Lime", 0x32CD32), ("Green", 0x00FF00), ("Mint", 0x98FF98), ("Teal", 0x008080),
        ("Turquoise", 0x40E0D0), ("Cyan", 0x00FFFF), ("Azure", 0x007FFF), ("Blue", 0x0000FF),
        ("Indigo", 0x4B0082), ("Violet", 0x9400D3), ("Purple", 0x8000FF), ("Magenta", 0xFF00FF),
        ("Pink", 0xFF69B4), ("Lavender", 0xE6BEFF), ("White", 0xFFFFFF),
    ].map { NamedColor(name: $0.0, rgb: hex(UInt32($0.1))) }

    public static let whitePresets: [WhitePreset] = [
        WhitePreset(name: "Candle", kelvin: 2200),
        WhitePreset(name: "Warm", kelvin: 2700),
        WhitePreset(name: "Soft", kelvin: 3000),
        WhitePreset(name: "Neutral", kelvin: 4000),
        WhitePreset(name: "Cool", kelvin: 5000),
        WhitePreset(name: "Day", kelvin: 5500),
        WhitePreset(name: "Daylight", kelvin: 6500),
    ]

    /// Short human name for a light mode: "Soft white", "Coral", "Fireplace".
    public static func describe(_ mode: LightMode?) -> String {
        switch mode {
        case .white(let k):
            if let preset = whitePresets.first(where: { $0.kelvin == k }) { return "\(preset.name) white" }
            return "\(k)K"
        case .color(let rgb):
            return colors.first(where: { $0.rgb == rgb })?.name ?? rgb.hex
        case .scene(let id):
            return scene(id)?.name ?? "Scene \(id)"
        case nil:
            return "Unknown"
        }
    }
}
