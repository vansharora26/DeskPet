import DeskPetCore
import SwiftUI

/// Daily briefing + end-of-day summary, built only from local data.
/// (No calendar integration: DeskPet never claims to know your events.)
struct TodayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hub: HubState
    @ObservedObject var pet: PetViewModel
    var enterFocusWorld: () -> Void = {}

    var body: some View {
        let cal = model.calendar
        let b = Briefing.build(model.data, now: model.now, calendar: cal)
        let showWrapUp = model.data.briefing.endOfDayEnabled
            && cal.minuteOfDay(model.now) >= model.data.briefing.endOfDayMinute

        ScrollView {
            VStack(alignment: .leading, spacing: DP.spacing) {
                Text(greeting).font(DP.body).foregroundStyle(.secondary)

                // Prominent entry into Focus Worlds.
                Button(action: enterFocusWorld) {
                    HStack(spacing: 12) {
                        Image(systemName: "mountain.2.fill").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enter Focus World").font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("Deep Focus · Study · Work Sprint · Recharge · Planning").font(DP.caption).opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill").font(.title2)
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: DP.radius, style: .continuous)
                        .fill(LinearGradient(colors: WorldTheme.lobby.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Focus Worlds (⌃⌥F)")

                // Suggested next action
                Card {
                    SectionTitle(text: "Suggested next step", symbol: "sparkles")
                    Text(b.suggestion).font(DP.body)
                }

                HStack(spacing: DP.spacing) {
                    Card {
                        SectionTitle(text: "Water", symbol: "drop.fill", tint: DP.water)
                        HStack(spacing: 12) {
                            ZStack {
                                ProgressRing(progress: Double(b.waterML) / Double(max(1, b.waterTarget)), tint: DP.water, lineWidth: 7)
                                Text("\(Int(min(1, Double(b.waterML) / Double(max(1, b.waterTarget))) * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppCommand.formatML(b.waterML)).font(DP.headline)
                                Text("of \(AppCommand.formatML(b.waterTarget))").font(DP.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("+ \(model.hydrationSettings.defaultServingML) ml") {
                            runInHub(.logWater(ml: nil), model: model, hub: hub)
                        }
                        .buttonStyle(PillButtonStyle(tint: DP.water))
                    }
                    Card {
                        SectionTitle(text: "Focus", symbol: "timer")
                        HStack(spacing: 12) {
                            ZStack {
                                ProgressRing(progress: Double(b.focusSessions) / Double(max(1, b.focusGoal)), tint: DP.accent, lineWidth: 7)
                                Text("\(b.focusSessions)/\(b.focusGoal)").font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(b.focusMinutes) min").font(DP.headline)
                                Text("\(b.breaks) break\(b.breaks == 1 ? "" : "s")").font(DP.caption).foregroundStyle(.secondary)
                            }
                        }
                        if model.focusTimerState == nil {
                            Button("Start \(model.focusSettings.focusMinutes) min") {
                                runInHub(.startFocus(minutes: nil, label: nil), model: model, hub: hub)
                            }
                            .buttonStyle(PillButtonStyle())
                        } else {
                            Button("Open timer") { hub.tab = .focus }.buttonStyle(PillButtonStyle(filled: false))
                        }
                    }
                }

                Card {
                    SectionTitle(text: "Due today", symbol: "checklist", tint: DP.mint,
                                 trailing: AnyView(Button("All tasks") { hub.showNotes = false; hub.taskFilter = .today; hub.tab = .tasks }
                                    .buttonStyle(.link).font(DP.caption)))
                    if b.dueToday.isEmpty {
                        Text("Nothing due today. Enjoy the breathing room.").font(DP.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(b.dueToday.prefix(6)) { item in
                            TaskRow(item: item, model: model, hub: hub, compact: true)
                        }
                    }
                }

                if !b.upcoming.isEmpty {
                    Card {
                        SectionTitle(text: "Coming up this week", symbol: "calendar", tint: DP.water)
                        ForEach(b.upcoming.prefix(5)) { item in
                            HStack {
                                Text(item.title).font(DP.body).lineLimit(1)
                                Spacer()
                                if let due = item.due {
                                    Text(AppCommand.formatDate(due, hasTime: item.dueHasTime, calendar: cal))
                                        .font(DP.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if showWrapUp {
                    Card {
                        SectionTitle(text: "Today’s wrap-up", symbol: "moon.stars.fill", tint: DP.xp)
                        Text(wrapUp(b)).font(DP.body)
                        if !b.completedToday.isEmpty {
                            ForEach(b.completedToday.prefix(5)) { item in
                                Label(item.title, systemImage: "checkmark.circle.fill")
                                    .font(DP.caption).foregroundStyle(DP.mint).lineLimit(1)
                            }
                        }
                    }
                }

                Text("DeskPet doesn’t read your calendar. Add deadlines to tasks to see them here.")
                    .font(DP.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var greeting: String {
        let h = model.calendar.component(.hour, from: model.now)
        let part = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        var s = "\(part)! \(pet.name) is here."
        if model.data.progression.gamificationEnabled && model.data.progression.showStreaks {
            let streak = model.data.progression.currentStreak(now: model.now, calendar: model.calendar)
            if streak >= 2 { s += " \(streak)-day streak." }
        }
        return s
    }

    private func wrapUp(_ b: Briefing) -> String {
        var parts: [String] = []
        parts.append("\(b.completedToday.count) task\(b.completedToday.count == 1 ? "" : "s") completed")
        parts.append("\(b.focusSessions) focus session\(b.focusSessions == 1 ? "" : "s") (\(b.focusMinutes) min)")
        parts.append("\(AppCommand.formatML(b.waterML)) of water")
        return parts.joined(separator: " · ") + ". Every bit counts."
    }
}
