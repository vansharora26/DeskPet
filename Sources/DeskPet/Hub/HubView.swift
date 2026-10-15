import DeskPetCore
import SwiftUI

enum HubTab: String, CaseIterable, Identifiable {
    case today, chat, water, focus, tasks, stats
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .chat: return "Chat"
        case .water: return "Water"
        case .focus: return "Focus"
        case .tasks: return "Tasks & Notes"
        case .stats: return "Stats"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max.fill"
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .water: return "drop.fill"
        case .focus: return "timer"
        case .tasks: return "checklist"
        case .stats: return "chart.bar.fill"
        }
    }

    var tint: Color {
        switch self {
        case .water: return DP.water
        case .focus: return DP.accent
        case .stats: return DP.xp
        case .tasks: return DP.mint
        default: return DP.accent
        }
    }
}

/// Shared navigation state for the hub window.
@MainActor
final class HubState: ObservableObject {
    @Published var tab: HubTab = .today
    /// Tasks tab shows notes instead of tasks.
    @Published var showNotes = false
    @Published var taskFilter: TaskFilter = .today
    @Published var search = ""
    /// Last action feedback inside the hub (with undo).
    @Published var feedback: CommandResult?
}

/// The compact companion window: a slim icon sidebar plus one focused panel.
struct HubView: View {
    @ObservedObject var state: HubState
    @ObservedObject var model: AppModel
    @ObservedObject var chat: ChatModel
    @ObservedObject var pet: PetViewModel
    @ObservedObject var settings: AppSettings
    var openSettings: (SettingsTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(HubTab.allCases) { tab in
                    Button { state.tab = tab } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 34)
                            .foregroundStyle(state.tab == tab ? Color.white : Color.secondary)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(state.tab == tab ? tab.tint : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(state.tab == tab ? .isSelected : [])
                    .keyboardShortcut(KeyEquivalent(Character("\(HubTab.allCases.firstIndex(of: tab)! + 1)")), modifiers: .command)
                }
                Spacer()
                Button { openSettings(.general) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 14)).frame(width: 36, height: 30)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings (⌘,)")
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(state.tab.title).font(DP.title(18))
                    Spacer()
                    if model.data.progression.gamificationEnabled {
                        LevelPill(progression: model.data.progression)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

                Group {
                    switch state.tab {
                    case .today: TodayView(model: model, hub: state, pet: pet)
                    case .chat: ChatView(chat: chat, openSettings: { openSettings(.ai) })
                    case .water: WaterView(model: model, hub: state, openSettings: { openSettings(.water) })
                    case .focus: FocusView(model: model, openSettings: { openSettings(.focus) })
                    case .tasks: TasksView(model: model, hub: state)
                    case .stats: StatsView(model: model, openSettings: { openSettings(.pet) })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if let fb = state.feedback {
                    FeedbackBanner(result: fb, onUndo: fb.undo.map { undo in { undo(); state.feedback = nil } })
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: fb.message) {
                            try? await Task.sleep(for: .seconds(5))
                            if state.feedback?.message == fb.message { state.feedback = nil }
                        }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 560)
        .animation(.easeOut(duration: 0.2), value: state.feedback?.message)
        .dpPanelStyle()
    }
}

struct LevelPill: View {
    var progression: Progression

    var body: some View {
        let p = progression.progressToNextLevel
        HStack(spacing: 6) {
            Image(systemName: "star.fill").foregroundStyle(DP.xp)
            Text("Lv \(progression.level)").font(.system(size: 11, weight: .bold, design: .rounded))
            ProgressView(value: Double(p.current), total: Double(max(1, p.needed)))
                .progressViewStyle(.linear).tint(DP.xp).frame(width: 50)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(DP.xp.opacity(0.12)))
        .help("\(progression.xp) XP · \(p.needed - p.current) XP to level \(progression.level + 1)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(progression.level), \(p.current) of \(p.needed) XP toward the next level")
    }
}

/// Small helper: run a command from a button and show feedback in the hub.
@MainActor
func runInHub(_ command: AppCommand, model: AppModel, hub: HubState) {
    let r = CommandExecutor(model: model).run(command)
    hub.feedback = r
}
