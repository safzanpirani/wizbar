import SwiftUI
import WizKit

/// Control Center style level slider: the filled part is the light itself.
struct LevelSlider: View {
    let value: Double            // 0...1
    let tint: RGB
    let active: Bool
    let onChange: (Double) -> Void
    var accessibilityStep: Double = 0.1

    private let height: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let width = max(height, geo.size.width * value)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(active ? Color(tint) : Color.primary.opacity(0.22))
                    .frame(width: width)
                    .shadow(color: active ? Color(tint).opacity(0.45) : .clear, radius: 6, y: 1)
                Image(systemName: value < 0.45 ? "sun.min.fill" : "sun.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? tint.ink : Color.primary.opacity(0.6))
                    .frame(width: height, height: height)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(1, max(0, drag.location.x / geo.size.width)))
            })
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.18), value: active)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(1, value + accessibilityStep))
            case .decrement: onChange(max(0, value - accessibilityStep))
            @unknown default: break
            }
        }
    }
}

/// Gradient track with a round thumb, for temperature, hue, saturation and speed.
struct ThumbSlider: View {
    let label: String
    let value: Double            // 0...1
    let track: [Color]
    let thumb: Color
    let valueText: String
    let onChange: (Double) -> Void

    private let thumbSize: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - thumbSize
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .frame(height: Metrics.trackHeight - 8)
                    .padding(.horizontal, 2)
                Circle()
                    .fill(thumb)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.28), radius: 2.5, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: usable * value)
            }
            .frame(height: Metrics.trackHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(1, max(0, (drag.location.x - thumbSize / 2) / usable)))
            })
        }
        .frame(height: Metrics.trackHeight)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(1, value + 0.05))
            case .decrement: onChange(max(0, value - 0.05))
            @unknown default: break
            }
        }
    }
}

/// Round color swatch with a selection ring.
struct Swatch: View {
    let colors: [RGB]
    let selected: Bool
    var size: CGFloat = 26
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(LinearGradient(colors: colors.map(Color.init), startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .frame(width: size, height: size)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.85 : 0), lineWidth: 2))
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
