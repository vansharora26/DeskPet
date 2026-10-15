import SwiftUI

/// DeskPet design tokens. Warm, friendly, and consistent across every panel.
enum DP {
    static let accent = Color(red: 0.93, green: 0.49, blue: 0.18)      // ginger
    static let water = Color(red: 0.24, green: 0.56, blue: 0.93)
    static let mint = Color(red: 0.18, green: 0.66, blue: 0.55)         // breaks & done
    static let xp = Color(red: 0.55, green: 0.40, blue: 0.86)
    static let danger = Color(red: 0.86, green: 0.27, blue: 0.30)

    static let radius: CGFloat = 12
    static let spacing: CGFloat = 12

    static func title(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let headline = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11)
}

/// Card container used for every section.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DP.radius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: DP.radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct SectionTitle: View {
    var text: String
    var symbol: String? = nil
    var tint: Color = DP.accent
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            Text(text).font(DP.headline)
            Spacer()
            if let trailing { trailing }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Circular progress used for water and focus goals.
struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        }
        .accessibilityHidden(true)
    }
}

/// Friendly empty state with the pet's voice.
struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(title).font(DP.headline)
            Text(message).font(DP.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = DP.accent
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(filled ? Color.white : tint)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.13)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Inline feedback banner with optional Undo.
struct FeedbackBanner: View {
    var result: CommandResult
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.message).font(DP.body)
                ForEach(result.details, id: \.self) { Text($0).font(DP.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if let onUndo, result.undo != nil {
                Button("Undo", action: onUndo).buttonStyle(PillButtonStyle(tint: color, filled: false))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch result.style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch result.style {
        case .success: return DP.mint
        case .info: return DP.water
        case .error: return DP.danger
        }
    }
}

extension View {
    /// Applies the user's chosen appearance (system/light/dark) to DeskPet windows.
    func dpPanelStyle() -> some View {
        self.tint(DP.accent)
    }
}
