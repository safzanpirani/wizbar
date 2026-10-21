import AppKit
import Combine
import SwiftUI
import WizKit

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: LightStore
    private let settings: AppSettings
    private let router: PanelRouter
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0
    private var showLevelUntil = Date.distantPast
    private var hideLevelTask: Task<Void, Never>?

    init(store: LightStore, settings: AppSettings, router: PanelRouter) {
        self.store = store
        self.settings = settings
        self.router = router
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView()
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(router))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        Publishers.CombineLatest3(store.$state, store.$connection, settings.$showBrightnessInMenuBar)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.render() }
            .store(in: &cancellables)
        settings.$bulbName
            .sink { [weak self] _ in DispatchQueue.main.async { self?.render() } }
            .store(in: &cancellables)
        store.$brightnessNudge
            .dropFirst()
            .sink { [weak self] _ in self?.flashLevel() }
            .store(in: &cancellables)

        installScrollMonitor()
        render()
    }

    // MARK: Rendering

    private func render() {
        guard let button = item.button else { return }
        let symbol: String
        switch store.connection {
        case .offline: symbol = "lightbulb.slash"
        default: symbol = store.state?.isOn == true ? "lightbulb.fill" : "lightbulb"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: settings.bulbName)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        button.image = image

        let showLevel = (settings.showBrightnessInMenuBar || Date() < showLevelUntil) && store.state?.isOn == true
        if showLevel, let level = store.state?.brightness {
            button.attributedTitle = NSAttributedString(string: "\(level)%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium),
            ])
        } else {
            button.title = ""
        }
        button.toolTip = tooltip
    }

    private var tooltip: String {
        let name = settings.bulbName
        switch store.connection {
        case .connecting: return "\(name): connecting"
        case .offline: return "\(name): offline"
        case .online:
            guard let state = store.state else { return name }
            return state.isOn ? "\(name): on, \(state.brightness)%, \(Catalog.describe(state.mode))" : "\(name): off"
        }
    }

    private func flashLevel() {
        showLevelUntil = Date().addingTimeInterval(1.6)
        render()
        hideLevelTask?.cancel()
        hideLevelTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        // Accessibility presses (VoiceOver, scripts) arrive without a mouse event.
        let event = NSApp.currentEvent
        let mouseUp = event?.type == .leftMouseUp
        let flags = event?.modifierFlags ?? []
        if event?.type == .rightMouseUp || (mouseUp && flags.contains(.control)) {
            showMenu()
        } else if mouseUp && flags.contains(.option) {
            Task { await store.togglePower() }
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover(page: PanelRouter.Page = .controls) {
        guard let button = item.button else { return }
        router.page = page
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverWillShow(_ notification: Notification) {
        store.isPanelOpen = true
        router.panelOpened()
    }

    func popoverDidClose(_ notification: Notification) {
        store.isPanelOpen = false
        router.page = .controls
    }

    private func showMenu() {
        let menu = NSMenu()
        let isOn = store.state?.isOn == true
        menu.addItem(withTitle: isOn ? "Turn Off" : "Turn On", action: #selector(menuToggle), keyEquivalent: "")
            .target = self

        if !settings.favorites.isEmpty {
            menu.addItem(.separator())
            for favorite in settings.favorites {
                let entry = NSMenuItem(title: "\(favorite.name)  \(favorite.brightness)%", action: #selector(menuFavorite(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = favorite.id
                entry.image = swatchImage(favorite.swatch)
                if let state = store.state, favorite.matches(state) { entry.state = .on }
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit WizBar", action: #selector(menuQuit), keyEquivalent: "q").target = self

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func swatchImage(_ colors: [RGB]) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            let ns = colors.map { NSColor($0) }
            if ns.count > 1, let gradient = NSGradient(colors: ns) {
                gradient.draw(in: path, angle: -45)
            } else {
                (ns.first ?? .white).setFill()
                path.fill()
            }
            NSColor.black.withAlphaComponent(0.15).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }

    @objc private func menuToggle() { Task { await store.togglePower() } }
    @objc private func menuSettings() { showPopover(page: .settings) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuFavorite(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let favorite = settings.favorites.first(where: { $0.id == id }) else { return }
        store.apply(favorite)
    }

    // MARK: Scroll to dim

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let button = item.button, event.window === button.window else { return event }
            handleScroll(event)
            return nil
        }
    }

    /// Scrolling up (finger or wheel, either scroll direction setting) brightens.
    private func handleScroll(_ event: NSEvent) {
        var dy = event.scrollingDeltaY
        if event.isDirectionInvertedFromDevice { dy = -dy }
        let pointsPerStep: CGFloat = event.hasPreciseScrollingDeltas ? 6 : 1
        scrollAccumulator += dy / pointsPerStep
        let steps = Int(scrollAccumulator)
        guard steps != 0 else { return }
        scrollAccumulator -= CGFloat(steps)
        let perStep = event.hasPreciseScrollingDeltas ? 2 : 5
        Task { await store.nudgeBrightness(by: steps * perStep) }
    }
}

extension NSColor {
    convenience init(_ rgb: RGB) {
        self.init(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
    }
}
