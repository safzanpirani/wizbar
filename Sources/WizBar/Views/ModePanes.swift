import SwiftUI
import WizKit

struct WhitePane: View {
    let state: BulbState
    @EnvironmentObject private var store: LightStore

    private static let trackStops = [2200, 2700, 3300, 4000, 5000, 6500].map { Color(Kelvin.color($0)) }

    private var kelvin: Int? {
        if case .white(let k) = state.mode { return k }
        return nil
    }

    var body: some View {
        let current = kelvin ?? 2700
        let span = Double(Kelvin.range.upperBound - Kelvin.range.lowerBound)
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Temperature", trailing: kelvin.map { "\($0)K" })
            ThumbSlider(
                label: "Temperature",
                value: Double(current - Kelvin.range.lowerBound) / span,
                track: Self.trackStops,
                thumb: Color(Kelvin.color(current)),
                valueText: "\(current) kelvin"
            ) { fraction in
                // Snap to 100K steps: finer steps are invisible and just add traffic.
                let k = Kelvin.range.lowerBound + Int((fraction * span / 100).rounded()) * 100
                if k != kelvin { store.setWhite(k) }
            }
            .opacity(kelvin == nil ? 0.55 : 1)

            HStack(spacing: 0) {
                ForEach(Catalog.whitePresets) { preset in
                    VStack(spacing: 5) {
                        Swatch(colors: [Kelvin.color(preset.kelvin)], selected: kelvin == preset.kelvin, size: 30) {
                            store.setWhite(preset.kelvin)
                        }
                        .help("\(preset.kelvin)K")
                        Text(preset.name)
                            .font(.system(size: 10, weight: kelvin == preset.kelvin ? .semibold : .regular))
                            .foregroundStyle(kelvin == preset.kelvin ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        }
    }
}

struct ColorPane: View {
    let state: BulbState
    @EnvironmentObject private var store: LightStore
    @ViewState private var hue: Double = 0.08
    @ViewState private var saturation: Double = 1

    private var rgb: RGB? {
        if case .color(let c) = state.mode { return c }
        return nil
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
    private static let rainbow = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(Catalog.colors) { color in
                    Swatch(colors: [color.rgb], selected: rgb == color.rgb, size: 24) {
                        store.setColor(color.rgb)
                    }
                    .help(color.name)
                }
            }

            SectionLabel(text: "Custom", trailing: rgb?.hex)
                .padding(.top, 4)
            ThumbSlider(
                label: "Hue",
                value: hue,
                track: Self.rainbow,
                thumb: Color(hue: hue, saturation: saturation, brightness: 1),
                valueText: "\(Int(hue * 360)) degrees"
            ) { value in
                hue = value
                send()
            }
            ThumbSlider(
                label: "Saturation",
                value: saturation,
                track: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                thumb: Color(hue: hue, saturation: saturation, brightness: 1),
                valueText: "\(Int(saturation * 100)) percent"
            ) { value in
                saturation = value
                send()
            }
        }
        .onAppear(perform: syncFromLight)
        .onChange(of: rgb) { syncFromLight() }
    }

    private func send() {
        store.setColor(RGB(hue: hue, saturation: saturation))
    }

    /// Follows the light unless the change came from these sliders (then the
    /// round trip through RGB would make the thumbs jitter).
    private func syncFromLight() {
        guard let rgb, rgb != RGB(hue: hue, saturation: saturation) else { return }
        let hs = rgb.hueSaturation
        hue = hs.hue
        saturation = hs.saturation
    }
}

struct ScenePane: View {
    let state: BulbState
    @EnvironmentObject private var store: LightStore

    private var sceneId: Int? {
        if case .scene(let id) = state.mode { return id }
        return nil
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        let active = sceneId.flatMap(Catalog.scene)
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Catalog.sceneGroups) { group in
                            Text(group.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: Self.columns, spacing: 6) {
                                ForEach(group.scenes) { scene in
                                    SceneTile(scene: scene, selected: scene.id == sceneId) {
                                        store.setScene(scene.id)
                                    }
                                    .id(scene.id)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .scrollIndicators(.never)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .onAppear {
                    if let sceneId { proxy.scrollTo(sceneId, anchor: .center) }
                }
            }

            if let active, active.animated {
                let speed = state.speed ?? 100
                HStack(spacing: 8) {
                    Image(systemName: "tortoise.fill")
                    ThumbSlider(
                        label: "Speed",
                        value: Double(speed - Speed.range.lowerBound) / Double(Speed.range.upperBound - Speed.range.lowerBound),
                        track: [Color.primary.opacity(0.12), Color.primary.opacity(0.28)],
                        thumb: Color(active.colors[0]),
                        valueText: "\(speed) percent"
                    ) { fraction in
                        let span = Double(Speed.range.upperBound - Speed.range.lowerBound)
                        let value = Speed.range.lowerBound + Int((fraction * span / 5).rounded()) * 5
                        if value != state.speed { store.setSpeed(value) }
                    }
                    Image(systemName: "hare.fill")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("Animation speed")
            }
        }
        .frame(height: Metrics.sceneHeight)
    }
}

private struct SceneTile: View {
    let scene: LightScene
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        let ink = RGB.average(scene.colors).ink
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: scene.symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Spacer(minLength: 0)
                Text(scene.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(ink)
            .padding(8)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: scene.colors.map(Color.init), startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.primary.opacity(0.85) : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 0.5)
            )
            .brightness(hovering ? 0.04 : 0)
            .scaleEffect(hovering ? 1.025 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityLabel(scene.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FavoritesRow: View {
    let state: BulbState
    @EnvironmentObject private var store: LightStore
    @EnvironmentObject private var settings: AppSettings

    private var alreadySaved: Bool {
        settings.favorites.contains { $0.mode == state.mode && $0.brightness == state.brightness }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Favorites")
            HStack(spacing: 6) {
                if settings.favorites.isEmpty {
                    Text("Save the current light to get back to it in one click.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(settings.favorites) { favorite in
                                FavoriteChip(favorite: favorite, active: favorite.matches(state))
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.addFavorite(from: state) }
                } label: {
                    Image(systemName: alreadySaved ? "star.fill" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(HoverButtonStyle(padding: 6))
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .disabled(alreadySaved || !settings.canAddFavorite || !state.isOn || state.mode == nil)
                .help(alreadySaved ? "Already saved" : settings.canAddFavorite ? "Save the current light" : "Favorites are full (\(AppSettings.maxFavorites))")
            }
        }
    }
}

private struct FavoriteChip: View {
    let favorite: Favorite
    let active: Bool
    @EnvironmentObject private var store: LightStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button { store.apply(favorite) } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: favorite.swatch.map(Color.init), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .frame(width: 12, height: 12)
                Text(favorite.name)
                    .font(.system(size: 11, weight: .medium))
                Text("\(favorite.brightness)%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
        }
        .buttonStyle(HoverButtonStyle(shape: AnyShape(Capsule()), padding: 0))
        .background(Capsule().fill(Color.primary.opacity(active ? 0.12 : 0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(active ? 0.5 : 0), lineWidth: 1))
        .contextMenu {
            Button("Move left") { settings.moveFavorite(favorite, by: -1) }
                .disabled(settings.favorites.first == favorite)
            Button("Move right") { settings.moveFavorite(favorite, by: 1) }
                .disabled(settings.favorites.last == favorite)
            Divider()
            Button("Remove", role: .destructive) {
                withAnimation { settings.removeFavorite(favorite) }
            }
        }
        .help("Right-click to reorder or remove")
    }
}
