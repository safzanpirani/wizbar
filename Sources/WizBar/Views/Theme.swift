import SwiftUI
import WizKit

/// SwiftUI's `@State` is a macro whose plugin ships only with Xcode. The
/// property wrapper behind it works the same under the Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

extension RGB {
    /// Legible icon/text color on top of this color.
    var ink: Color { luminance > 0.4 ? Color.black.opacity(0.7) : Color.white.opacity(0.95) }

    static func average(_ colors: [RGB]) -> RGB {
        guard !colors.isEmpty else { return RGB(255, 255, 255) }
        let n = colors.count
        return RGB(colors.map(\.r).reduce(0, +) / n, colors.map(\.g).reduce(0, +) / n, colors.map(\.b).reduce(0, +) / n)
    }

    init(hue: Double, saturation: Double) {
        let ns = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB)!
        self.init(Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }

    var hueSaturation: (hue: Double, saturation: Double) {
        let ns = NSColor(self).usingColorSpace(.sRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s))
    }
}

enum Metrics {
    static let panelWidth: CGFloat = 340
    static let padding: CGFloat = 16
    static let sceneHeight: CGFloat = 236
    static let trackHeight: CGFloat = 22
}

/// Plain button with a hover wash, for icon-only and chip controls.
struct HoverButtonStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(Circle())
    var padding: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, shape: shape, padding: padding)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let shape: AnyShape
        let padding: CGFloat
        @ViewState private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(padding)
                .contentShape(shape)
                .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hovering && isEnabled ? 0.08 : 0)))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text)
            Spacer()
            if let trailing {
                Text(trailing).monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
}
