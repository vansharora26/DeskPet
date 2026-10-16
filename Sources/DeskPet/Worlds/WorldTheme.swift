import DeskPetCore
import SwiftUI

/// Visual identity for each world. One design system (shared components,
/// spacing and shapes) with a distinct palette, type and mood per world.
struct WorldTheme {
    let world: FocusWorld
    /// Text/controls drawn directly on the scene.
    let ink: Color
    let softInk: Color
    let accent: Color
    /// Floating panels (cards) over the scene.
    let panel: Color
    let panelInk: Color
    let panelStroke: Color
    let isDark: Bool
    /// Panels can differ from the scene (Study: dark room, cream notebook).
    var panelIsDark: Bool { world == .deepFocus }
    let design: Font.Design
    let symbol: String
    /// Minimal-scenery gradient (also the base of illustrated scenes).
    let gradient: [Color]

    func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    /// The big timer numerals, styled per world.
    func timerFont(_ size: CGFloat) -> Font {
        switch world {
        case .deepFocus: return .system(size: size, weight: .ultraLight, design: .rounded).monospacedDigit()
        case .study: return .system(size: size, weight: .regular, design: .serif).monospacedDigit()
        case .workSprint: return .system(size: size, weight: .heavy, design: .default).monospacedDigit()
        case .recharge: return .system(size: size, weight: .light, design: .rounded).monospacedDigit()
        case .planning: return .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
        }
    }

    static func of(_ world: FocusWorld) -> WorldTheme {
        switch world {
        case .deepFocus:
            return WorldTheme(world: world, ink: Color(red: 0.88, green: 0.92, blue: 0.95), softInk: Color(red: 0.6, green: 0.68, blue: 0.74),
                              accent: Color(red: 0.98, green: 0.78, blue: 0.45),
                              panel: Color(red: 0.08, green: 0.11, blue: 0.15).opacity(0.72), panelInk: Color(red: 0.88, green: 0.92, blue: 0.95),
                              panelStroke: Color.white.opacity(0.08), isDark: true, design: .rounded, symbol: "moon.stars.fill",
                              gradient: [Color(red: 0.04, green: 0.06, blue: 0.13), Color(red: 0.07, green: 0.13, blue: 0.18)])
        case .study:
            return WorldTheme(world: world, ink: Color(red: 0.98, green: 0.93, blue: 0.84), softInk: Color(red: 0.86, green: 0.76, blue: 0.64),
                              accent: Color(red: 0.93, green: 0.6, blue: 0.32),
                              panel: Color(red: 0.99, green: 0.96, blue: 0.9).opacity(0.94), panelInk: Color(red: 0.25, green: 0.17, blue: 0.12),
                              panelStroke: Color(red: 0.55, green: 0.4, blue: 0.28).opacity(0.25), isDark: true, design: .serif, symbol: "books.vertical.fill",
                              gradient: [Color(red: 0.34, green: 0.23, blue: 0.18), Color(red: 0.2, green: 0.13, blue: 0.1)])
        case .workSprint:
            return WorldTheme(world: world, ink: Color(red: 0.07, green: 0.1, blue: 0.2), softInk: Color(red: 0.36, green: 0.42, blue: 0.55),
                              accent: Color(red: 0.2, green: 0.42, blue: 1.0),
                              panel: Color.white.opacity(0.9), panelInk: Color(red: 0.07, green: 0.1, blue: 0.2),
                              panelStroke: Color(red: 0.2, green: 0.35, blue: 0.7).opacity(0.14), isDark: false, design: .default, symbol: "bolt.fill",
                              gradient: [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.87, green: 0.91, blue: 0.98)])
        case .recharge:
            return WorldTheme(world: world, ink: Color(red: 0.32, green: 0.22, blue: 0.38), softInk: Color(red: 0.5, green: 0.42, blue: 0.56),
                              accent: Color(red: 0.4, green: 0.68, blue: 0.52),
                              panel: Color.white.opacity(0.55), panelInk: Color(red: 0.32, green: 0.22, blue: 0.38),
                              panelStroke: Color.white.opacity(0.6), isDark: false, design: .rounded, symbol: "leaf.fill",
                              gradient: [Color(red: 1.0, green: 0.84, blue: 0.74), Color(red: 0.8, green: 0.77, blue: 0.95)])
        case .planning:
            return WorldTheme(world: world, ink: Color(red: 0.15, green: 0.2, blue: 0.3), softInk: Color(red: 0.4, green: 0.46, blue: 0.56),
                              accent: Color(red: 0.97, green: 0.6, blue: 0.2),
                              panel: Color.white.opacity(0.88), panelInk: Color(red: 0.15, green: 0.2, blue: 0.3),
                              panelStroke: Color(red: 0.97, green: 0.6, blue: 0.2).opacity(0.18), isDark: false, design: .rounded, symbol: "sun.horizon.fill",
                              gradient: [Color(red: 0.99, green: 0.95, blue: 0.86), Color(red: 0.84, green: 0.92, blue: 1.0)])
        }
    }

    /// Neutral dusk palette for the mode-selection screen.
    static let lobby = WorldTheme(world: .deepFocus, ink: .white, softInk: Color.white.opacity(0.7),
                                  accent: DP.accent, panel: Color.white.opacity(0.08), panelInk: .white,
                                  panelStroke: Color.white.opacity(0.12), isDark: true, design: .rounded, symbol: "sparkles",
                                  gradient: [Color(red: 0.12, green: 0.1, blue: 0.24), Color(red: 0.32, green: 0.18, blue: 0.36),
                                             Color(red: 0.62, green: 0.34, blue: 0.36)])
}

/// A floating card in the world's style.
struct WorldPanel<Content: View>: View {
    let theme: WorldTheme
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .foregroundStyle(theme.panelInk)
            // Controls inside a panel follow the panel's brightness, not the scene's.
            .environment(\.worldOnPanel, true)
            .environment(\.colorScheme, theme.panelIsDark ? .dark : .light)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.panelStroke))
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.08), radius: 14, y: 6)
    }
}

private struct WorldOnPanelKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True inside a WorldPanel, so controls use the panel's ink rather than the scene's.
    var worldOnPanel: Bool {
        get { self[WorldOnPanelKey.self] }
        set { self[WorldOnPanelKey.self] = newValue }
    }
}

/// Pill button in the world's accent.
struct WorldButtonStyle: ButtonStyle {
    let theme: WorldTheme
    var prominent = true
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        WorldButtonBody(configuration: configuration, theme: theme, prominent: prominent, large: large)
    }
}

private struct WorldButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let theme: WorldTheme
    let prominent: Bool
    let large: Bool
    @Environment(\.worldOnPanel) private var onPanel
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let ink = onPanel ? theme.panelInk : theme.ink
        configuration.label
            .font(theme.display(large ? 16 : 13, weight: .semibold))
            .padding(.horizontal, large ? 26 : 16)
            .padding(.vertical, large ? 12 : 8)
            .foregroundStyle(prominent ? (theme.world == .deepFocus ? Color(red: 0.1, green: 0.08, blue: 0.04) : .white) : ink)
            .background(Capsule().fill(prominent ? theme.accent : ink.opacity(0.1)))
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : ink.opacity(0.18)))
            .opacity(!isEnabled ? 0.45 : (configuration.isPressed ? 0.75 : 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}
