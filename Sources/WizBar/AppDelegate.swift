import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let router = PanelRouter()
    private lazy var store = LightStore(settings: settings)
    private var statusItem: StatusItemController?
    private let hotKeys = HotKeys()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(store: store, settings: settings, router: router)
        store.start()

        settings.$hotkeysEnabled
            .sink { [weak self] enabled in self?.updateHotKeys(enabled) }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.store.refresh(force: true) }
            }
            .store(in: &cancellables)
    }

    private func updateHotKeys(_ enabled: Bool) {
        guard enabled else {
            hotKeys.unregisterAll()
            return
        }
        hotKeys.register(Shortcut.all.map { shortcut in
            HotKeys.Binding(keyCode: shortcut.keyCode) { [weak self] in
                guard let self else { return }
                Task {
                    switch shortcut {
                    case .toggle: await self.store.togglePower()
                    case .brighter: await self.store.nudgeBrightness(by: 10)
                    case .dimmer: await self.store.nudgeBrightness(by: -10)
                    }
                }
            }
        })
    }
}

enum Shortcut: CaseIterable {
    case toggle, brighter, dimmer

    static let all = allCases

    var keyCode: Int {
        switch self {
        case .toggle: return kVK_ANSI_L
        case .brighter: return kVK_ANSI_Equal
        case .dimmer: return kVK_ANSI_Minus
        }
    }

    var key: String {
        switch self {
        case .toggle: return "L"
        case .brighter: return "="
        case .dimmer: return "-"
        }
    }

    var title: String {
        switch self {
        case .toggle: return "Turn the light on or off"
        case .brighter: return "Brighter"
        case .dimmer: return "Dimmer"
        }
    }
}
