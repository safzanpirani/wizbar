import Foundation
import ServiceManagement
import WizKit

struct Favorite: Codable, Identifiable, Equatable {
    var id = UUID()
    var mode: LightMode
    var brightness: Int
    var speed: Int?

    var name: String { Catalog.describe(mode) }

    var swatch: [RGB] {
        switch mode {
        case .white(let k): return [Kelvin.color(k)]
        case .color(let c): return [c]
        case .scene(let id): return Catalog.scene(id)?.colors ?? [Kelvin.color(2700)]
        }
    }

    func matches(_ state: BulbState) -> Bool {
        state.isOn && state.mode == mode && state.brightness == brightness
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let defaultIP = "192.168.0.162"
    static let maxFavorites = 8

    private let defaults = UserDefaults.standard

    @Published var bulbIP: String { didSet { defaults.set(bulbIP, forKey: "bulbIP") } }
    @Published var bulbName: String { didSet { defaults.set(bulbName, forKey: "bulbName") } }
    @Published var showBrightnessInMenuBar: Bool { didSet { defaults.set(showBrightnessInMenuBar, forKey: "showBrightness") } }
    @Published var hotkeysEnabled: Bool { didSet { defaults.set(hotkeysEnabled, forKey: "hotkeys") } }
    @Published private(set) var favorites: [Favorite] {
        didSet { defaults.set(try? JSONEncoder().encode(favorites), forKey: "favorites") }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?

    init() {
        bulbIP = defaults.string(forKey: "bulbIP") ?? Self.defaultIP
        bulbName = defaults.string(forKey: "bulbName") ?? "Bedroom"
        showBrightnessInMenuBar = defaults.object(forKey: "showBrightness") as? Bool ?? false
        hotkeysEnabled = defaults.object(forKey: "hotkeys") as? Bool ?? true
        favorites = (defaults.data(forKey: "favorites")).flatMap { try? JSONDecoder().decode([Favorite].self, from: $0) } ?? []
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var canAddFavorite: Bool { favorites.count < Self.maxFavorites }

    func addFavorite(from state: BulbState) {
        guard let mode = state.mode, canAddFavorite else { return }
        let favorite = Favorite(mode: mode, brightness: state.brightness, speed: state.speed)
        guard !favorites.contains(where: { $0.mode == favorite.mode && $0.brightness == favorite.brightness }) else { return }
        favorites.append(favorite)
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
    }

    func moveFavorite(_ favorite: Favorite, by offset: Int) {
        guard let index = favorites.firstIndex(of: favorite) else { return }
        let target = index + offset
        guard favorites.indices.contains(target) else { return }
        favorites.swapAt(index, target)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
