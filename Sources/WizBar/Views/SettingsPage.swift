import Network
import SwiftUI
import WizKit

struct SettingsPage: View {
    @EnvironmentObject private var store: LightStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: PanelRouter

    @ViewState private var address = ""
    @ViewState private var testing = false
    @ViewState private var testResult: Result<SystemInfo, Error>?

    private var addressValid: Bool { IPv4Address(address.trimmingCharacters(in: .whitespaces)) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { close() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(HoverButtonStyle(shape: AnyShape(Capsule()), padding: 5))
                .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 56, height: 1)
            }

            group("Bulb") {
                field("Name") {
                    TextField("Bedroom", text: $settings.bulbName)
                        .textFieldStyle(.roundedBorder)
                }
                field("Address") {
                    HStack(spacing: 6) {
                        TextField(AppSettings.defaultIP, text: $address)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .onSubmit(commitAddress)
                        Button(testing ? "Testing…" : "Test") { test() }
                            .disabled(!addressValid || testing)
                    }
                }
                testLine
            }

            group("Menu bar") {
                Toggle("Show brightness next to the icon", isOn: $settings.showBrightnessInMenuBar)
                hint("Scroll over the icon to dim. Option-click it to switch the light on or off. Right-click for favorites.")
            }

            group("Keyboard") {
                Toggle("Shortcuts work in any app", isOn: $settings.hotkeysEnabled)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Shortcut.all, id: \.key) { shortcut in
                        HStack {
                            Text(shortcut.title)
                            Spacer()
                            Text(HotKeys.modifierLabel + shortcut.key)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                        }
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(settings.hotkeysEnabled ? .primary : .secondary)
                hint("In this panel: Space switches the light, arrow keys change brightness, 1 2 3 pick a tab.")
            }

            group("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.launchAtLoginError {
                    hint(error).foregroundStyle(.red)
                }
            }

            HStack {
                Text(versionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit WizBar") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear { address = settings.bulbIP }
        .onDisappear(perform: commitAddress)
    }

    @ViewBuilder
    private var testLine: some View {
        if !addressValid && !address.isEmpty {
            hint("Enter an IPv4 address, like \(AppSettings.defaultIP).").foregroundStyle(.red)
        } else {
            switch testResult {
            case .success(let info):
                Label(
                    [info.module, info.firmware.map { "firmware \($0)" }].compactMap { $0 }.joined(separator: ", ").ifEmpty("Connected"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.green)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            case nil:
                hint("WiZ bulbs only answer on the local network. Find the address in the WiZ app under the light's settings, or in your router.")
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8, content: content)
                .font(.system(size: 12))
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 56, alignment: .leading)
            content()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "WizBar \(version)"
    }

    private func commitAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        if IPv4Address(trimmed) != nil, trimmed != settings.bulbIP {
            settings.bulbIP = trimmed
        }
    }

    private func close() {
        commitAddress()
        router.page = .controls
    }

    private func test() {
        commitAddress()
        testing = true
        testResult = nil
        Task {
            do {
                let info = try await store.systemInfo()
                testResult = .success(info)
                await store.refresh(force: true)
            } catch {
                testResult = .failure(error)
            }
            testing = false
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
