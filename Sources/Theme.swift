import SwiftUI

enum Theme {
    static let bg = Color(red: 0.086, green: 0.063, blue: 0.051)        // #16100D warm charcoal
    static let panel = Color(red: 0.133, green: 0.098, blue: 0.075)     // #221913
    static let panelHi = Color(red: 0.180, green: 0.129, blue: 0.094)   // #2E2118
    static let line = Color.white.opacity(0.08)

    static let accent = Color(red: 1.0, green: 0.549, blue: 0.102)      // #FF8C1A orange
    static let amber = Color(red: 1.0, green: 0.741, blue: 0.290)       // #FFBD4A
    static let ember = Color(red: 0.902, green: 0.318, blue: 0.098)     // #E65119
    static let onAccent = Color(red: 0.169, green: 0.078, blue: 0.020)  // dark brown text on orange

    static let textHi = Color(red: 1.0, green: 0.949, blue: 0.902)
    static let textLo = Color(red: 0.776, green: 0.667, blue: 0.584)

    static let accentGradient = LinearGradient(colors: [amber, accent], startPoint: .top, endPoint: .bottom)
}

// MARK: - Button styles

struct AccentButton: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 13, weight: .semibold))
            .padding(.horizontal, large ? 20 : 14)
            .padding(.vertical, large ? 9 : 6)
            .background(Capsule().fill(Theme.accentGradient))
            .foregroundStyle(Theme.onAccent)
            .shadow(color: Theme.accent.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct GhostButton: ButtonStyle {
    var tint: Color = Theme.textHi
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.panelHi.opacity(configuration.isPressed ? 1 : 0.7)))
            .overlay(Capsule().strokeBorder(Theme.line))
            .foregroundStyle(tint)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct IconButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(Circle().fill(Theme.panelHi.opacity(configuration.isPressed ? 1 : 0.7)))
            .overlay(Circle().strokeBorder(Theme.line))
            .foregroundStyle(Theme.textHi)
    }
}

// MARK: - Shared bits

/// Rounded orange tile with the app's initials; hue shifts slightly per app.
struct AppTile: View {
    let name: String
    let size: CGFloat

    var body: some View {
        let hue = 0.02 + Double(name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 9) / 100
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hue: hue + 0.05, saturation: 0.75, brightness: 1.0),
                         Color(hue: hue, saturation: 0.9, brightness: 0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(monogram)
                    .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .frame(width: size, height: size)
            .shadow(color: Theme.accent.opacity(0.3), radius: size * 0.14, y: size * 0.05)
    }

    private var monogram: String {
        let words = name.split(separator: " ")
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array(name.prefix(2))
        return String(letters).uppercased()
    }
}

struct EngineBadge: View {
    let engine: Engine
    var body: some View {
        Text(engine.label)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4)))
            .foregroundStyle(Theme.amber)
    }
}

struct PulseDot: View {
    var color: Color
    @StateObject private var dim = ViewState(false)
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(dim.value ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dim.value)
            .onAppear { dim.value = true }
    }
}

/// Local view state. The Command Line Tools don't ship the plugin behind SwiftUI's @State
/// macro, so views keep small bits of state in this instead (use with @StateObject).
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
