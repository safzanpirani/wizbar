import Combine
import Foundation
import os
import WizKit

@MainActor
final class LightStore: ObservableObject {
    enum Connection: Equatable {
        case connecting
        case online
        case offline(message: String, localNetworkHint: Bool)
    }

    @Published private(set) var state: BulbState?
    @Published private(set) var connection: Connection = .connecting
    /// Bumped on every brightness change made from outside the panel
    /// (scroll, shortcuts) so the menu bar can show the level briefly.
    @Published private(set) var brightnessNudge = 0

    let settings: AppSettings
    private let client = WizClient()

    private var pending: PilotChange?
    private var sender: Task<Void, Never>?
    private var reconcile: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    private var lastLocalChange = Date.distantPast
    private var failedReads = 0
    private var ipObserver: AnyCancellable?

    var isPanelOpen = false {
        didSet {
            guard isPanelOpen != oldValue else { return }
            startPolling()
        }
    }

    init(settings: AppSettings) {
        self.settings = settings
        ipObserver = settings.$bulbIP
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                state = nil
                connection = .connecting
                Task { await self.refresh(force: true) }
            }
    }

    private var ip: String { settings.bulbIP }

    // MARK: Reading

    /// Reads the bulb. Unforced reads skip applying the result while the user is
    /// mid-gesture, so a poll never yanks a slider back.
    func refresh(force: Bool = false) async {
        do {
            let fresh = try await client.getPilot(ip: ip)
            connection = .online
            failedReads = 0
            let busy = pending != nil || sender != nil || Date().timeIntervalSince(lastLocalChange) < 1.5
            if force ? (pending == nil && sender == nil) : !busy {
                state = fresh
            }
        } catch {
            failedReads += 1
            // One dropped poll on Wi-Fi is noise; two in a row means the bulb is gone.
            if state == nil || failedReads >= 2 { fail(error) }
        }
    }

    func systemInfo() async throws -> SystemInfo {
        try await client.systemInfo(ip: ip)
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let seconds: Double = self.isPanelOpen ? 2.5 : 30
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func start() { startPolling() }

    // MARK: Writing

    private func send(_ change: PilotChange) {
        lastLocalChange = Date()
        if let state { self.state = state.applying(change) }
        if pending == nil { pending = change } else { pending!.merge(change) }
        reconcile?.cancel()
        if sender == nil {
            sender = Task { await drain() }
        }
    }

    /// Sends the newest merged change, then whatever piled up during that round
    /// trip. A dragged slider therefore sends at the bulb's pace, not the mouse's.
    private func drain() async {
        while let change = pending {
            pending = nil
            do {
                try await client.setPilot(ip: ip, change: change)
                connection = .online
                failedReads = 0
            } catch {
                pending = nil
                fail(error)
                break
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        sender = nil
        reconcile = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.refresh(force: true)
        }
    }

    private func fail(_ error: Error) {
        log.error("bulb request failed: \(String(describing: error), privacy: .public)")
        let wiz = error as? WizError
        connection = .offline(
            message: error.localizedDescription,
            localNetworkHint: wiz?.mayBeLocalNetworkPermission ?? false
        )
    }

    // MARK: Actions

    /// Toggles from a fresh read when the panel is closed, since the cached
    /// state can be 30 s old and the WiZ app may have changed it.
    func togglePower() async {
        if !isPanelOpen || state == nil { await refresh(force: true) }
        guard let state else { return }
        send(state.isOn ? .off : PilotChange(on: true))
    }

    func setOn(_ on: Bool) {
        send(on ? PilotChange(on: true) : .off)
    }

    func setBrightness(_ value: Int) {
        send(PilotChange(on: true, brightness: Brightness.clamp(value)))
    }

    /// Relative change used by scroll and shortcuts.
    func nudgeBrightness(by delta: Int) async {
        if !isPanelOpen && Date().timeIntervalSince(lastLocalChange) > 5 { await refresh(force: true) }
        guard let state, let target = Brightness.relative(isOn: state.isOn, current: state.brightness, delta: delta) else { return }
        if state.isOn && target == state.brightness { brightnessNudge += 1; return }
        send(PilotChange(on: true, brightness: target))
        brightnessNudge += 1
    }

    func setWhite(_ kelvin: Int) {
        send(PilotChange(on: true, mode: .white(kelvin: Kelvin.clamp(kelvin))))
    }

    func setColor(_ rgb: RGB) {
        send(PilotChange(on: true, mode: .color(rgb)))
    }

    func setScene(_ id: Int) {
        send(PilotChange(on: true, mode: .scene(id: id)))
    }

    func setSpeed(_ speed: Int) {
        send(PilotChange(on: true, speed: Speed.clamp(speed)))
    }

    func apply(_ favorite: Favorite) {
        send(PilotChange(on: true, brightness: favorite.brightness, mode: favorite.mode, speed: favorite.speed))
    }
}

private let log = Logger(subsystem: "dev.safzan.wizbar", category: "bulb")
