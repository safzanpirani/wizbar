import AppKit
import SwiftUI
import WizKit

@MainActor
final class PanelRouter: ObservableObject {
    enum Page { case controls, settings }

    enum Tab: String, CaseIterable, Identifiable {
        case white = "White", color = "Color", scenes = "Scenes"
        var id: String { rawValue }

        init(_ mode: LightMode?) {
            switch mode {
            case .color: self = .color
            case .scene: self = .scenes
            default: self = .white
            }
        }
    }

    @Published var page: Page = .controls
    @Published var tab: Tab = .white
    @Published private(set) var openCount = 0

    func panelOpened() { openCount += 1 }
}

struct PanelView: View {
    @EnvironmentObject private var store: LightStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PanelRouter

    var body: some View {
        ZStack(alignment: .top) {
            glow
            Group {
                switch router.page {
                case .controls: ControlsPage()
                case .settings: SettingsPage()
                }
            }
            .padding(Metrics.padding)
        }
        .frame(width: Metrics.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The panel takes on the light's own color, faintly, while it is on.
    private var glow: some View {
        let on = store.state?.isOn == true && router.page == .controls
        let tint = Color(store.state?.displayColor ?? RGB(255, 255, 255))
        return LinearGradient(colors: [tint.opacity(on ? 0.30 : 0), tint.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.4), value: store.state?.displayColor)
            .animation(.easeOut(duration: 0.3), value: on)
            .allowsHitTesting(false)
    }
}

private struct ControlsPage: View {
    @EnvironmentObject private var store: LightStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PanelRouter
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Header()
                .padding(.bottom, 14)

            if let state = store.state {
                if case .offline = store.connection {
                    LostContactBanner()
                        .padding(.bottom, 12)
                }
                controls(state)
            } else if case .offline(let message, let hint) = store.connection {
                OfflineCard(message: message, localNetworkHint: hint)
            } else {
                ConnectingCard()
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true; syncTab() }
        .onChange(of: router.openCount) { focused = true; syncTab() }
        .onChange(of: Tabbed(store.state?.mode)) { syncTab() }
        .onKeyPress(.space) { Task { await store.togglePower() }; return .handled }
        .onKeyPress(.upArrow) { nudge(5) }
        .onKeyPress(.rightArrow) { nudge(5) }
        .onKeyPress(.downArrow) { nudge(-5) }
        .onKeyPress(.leftArrow) { nudge(-5) }
        .onKeyPress(characters: .init(charactersIn: "123,")) { press in
            switch press.characters {
            case "1": router.tab = .white
            case "2": router.tab = .color
            case "3": router.tab = .scenes
            case "," where press.modifiers.contains(.command): router.page = .settings
            default: return .ignored
            }
            return .handled
        }
    }

    private func nudge(_ delta: Int) -> KeyPress.Result {
        Task { await store.nudgeBrightness(by: delta) }
        return .handled
    }

    private func syncTab() {
        if let mode = store.state?.mode { router.tab = .init(mode) }
    }

    @ViewBuilder
    private func controls(_ state: BulbState) -> some View {
        HStack(spacing: 10) {
            LevelSlider(
                value: Double(state.brightness - Brightness.floor) / Double(100 - Brightness.floor),
                tint: state.displayColor,
                active: state.isOn
            ) { fraction in
                store.setBrightness(Brightness.floor + Int((fraction * Double(100 - Brightness.floor)).rounded()))
            }
            Text("\(state.brightness)%")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(state.isOn ? .primary : .secondary)
                .frame(width: 38, alignment: .trailing)
        }

        Picker("Mode", selection: $router.tab) {
            ForEach(PanelRouter.Tab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.top, 16)

        Group {
            switch router.tab {
            case .white: WhitePane(state: state)
            case .color: ColorPane(state: state)
            case .scenes: ScenePane(state: state)
            }
        }
        .padding(.top, 14)

        FavoritesRow(state: state)
            .padding(.top, 18)
    }
}

/// Compares only the kind of mode, so a temperature drag does not count as a change.
private struct Tabbed: Equatable {
    let tab: PanelRouter.Tab?
    init(_ mode: LightMode?) { tab = mode.map(PanelRouter.Tab.init) }
}

private struct Header: View {
    @EnvironmentObject private var store: LightStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PanelRouter

    var body: some View {
        HStack(spacing: 12) {
            PowerOrb(state: store.state) { Task { await store.togglePower() } }
                .disabled(store.state == nil)

            VStack(alignment: .leading, spacing: 2) {
                Text(settings.bulbName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            if let rssi = store.state?.rssi, store.connection == .online {
                Image(systemName: "wifi", variableValue: signal(rssi))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Wi-Fi signal \(rssi) dBm")
            }

            Button { router.page = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(HoverButtonStyle())
            .help("Settings (⌘,)")
        }
    }

    private var statusLine: String {
        guard let state = store.state else {
            if case .offline = store.connection { return "Offline" }
            return "Connecting…"
        }
        guard state.isOn else { return "Off" }
        return "On · \(state.brightness)% · \(Catalog.describe(state.mode))"
    }

    private func signal(_ rssi: Int) -> Double {
        min(1, max(0.1, Double(rssi + 90) / 40))
    }
}

private struct PowerOrb: View {
    let state: BulbState?
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        let on = state?.isOn == true
        let color = state?.displayColor ?? RGB(255, 255, 255)
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(on
                          ? AnyShapeStyle(RadialGradient(colors: [Color(color).opacity(0.75), Color(color)], center: .center, startRadius: 2, endRadius: 24))
                          : AnyShapeStyle(Color.primary.opacity(hovering ? 0.12 : 0.08)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(on ? 0.1 : 0.06), lineWidth: 0.5))
                    .shadow(color: on ? Color(color).opacity(0.6) : .clear, radius: hovering ? 12 : 9, y: 2)
                Image(systemName: "power")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(on ? color.ink : Color.secondary)
            }
            .frame(width: 44, height: 44)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .animation(.easeOut(duration: 0.25), value: on)
        .animation(.easeOut(duration: 0.35), value: color)
        .help(on ? "Turn off (Space)" : "Turn on (Space)")
        .accessibilityLabel(on ? "Turn off" : "Turn on")
    }
}

private struct LostContactBanner: View {
    @EnvironmentObject private var store: LightStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Lost contact with the bulb")
                .font(.system(size: 12))
            Spacer()
            Button("Retry") { Task { await store.refresh(force: true) } }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.12)))
    }
}

private struct ConnectingCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Looking for \(settings.bulbName) at \(settings.bulbIP)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct OfflineCard: View {
    let message: String
    let localNetworkHint: Bool
    @EnvironmentObject private var store: LightStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PanelRouter
    @ViewState private var retrying = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text("Can't reach \(settings.bulbName)")
                .font(.system(size: 14, weight: .semibold))
            Text("\(message) WizBar looks for it at \(settings.bulbIP), which only answers on your home Wi-Fi.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if localNetworkHint {
                Text("If you are home, allow WizBar in Privacy & Security › Local Network.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    retrying = true
                    Task { await store.refresh(force: true); retrying = false }
                } label: {
                    Text(retrying ? "Trying…" : "Try again").frame(minWidth: 70)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(retrying)
                if localNetworkHint {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!)
                    }
                } else {
                    Button("Change address") { router.page = .settings }
                }
            }
            .controlSize(.regular)
            .padding(.top, 6)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}
