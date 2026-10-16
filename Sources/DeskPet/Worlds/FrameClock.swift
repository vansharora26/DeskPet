import Combine
import SwiftUI

/// A plain, low-rate clock for animation and countdown displays. Unlike a
/// `TimelineView(.periodic(from: .now…))` rebuilt inside a frequently
/// re-evaluated body, it ticks exactly at its interval, only while the view is
/// on screen, and only the small view that owns it re-renders.
@MainActor
final class FrameClock: ObservableObject {
    @Published private(set) var now = Date()
    private let interval: TimeInterval
    private var timer: Timer?

    init(interval: TimeInterval) { self.interval = interval }

    func start() {
        guard timer == nil else { return }
        now = Date()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        t.tolerance = interval * 0.2   // let macOS coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Re-renders `content` every `interval` seconds while visible.
struct Ticking<Content: View>: View {
    @StateObject private var clock: FrameClock
    private let content: (Date) -> Content

    init(every interval: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        _clock = StateObject(wrappedValue: FrameClock(interval: interval))
        self.content = content
    }

    var body: some View {
        content(clock.now)
            .onAppear { clock.start() }
            .onDisappear { clock.stop() }
    }
}
