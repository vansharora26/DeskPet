import DeskPetCore
import Foundation
import IOKit.ps

/// Reads the internal battery (level, charging) and publishes how the cat should feel.
/// Updates on macOS power-source notifications, with a slow poll as a backstop.
/// Macs without a battery report `.none` and nothing changes.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var reading: BatteryReading?
    @Published private(set) var mood: BatteryMood = .none
    /// Called when the mood changes (old, new).
    var onChange: (BatteryMood, BatteryMood) -> Void = { _, _ in }
    /// Turned off in Settings → behaves like a Mac without a battery.
    var isEnabled: () -> Bool = { true }
    /// For previews and tests.
    var override: BatteryReading?

    private var source: CFRunLoopSource?
    private var timer: Timer?

    /// The mood the cat should show right now (respects the setting).
    var effectiveMood: BatteryMood { isEnabled() ? mood : .none }

    func start() {
        refresh()
        guard source == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { monitor.refresh() } }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let r = override ?? Self.read()
        if r != reading { reading = r }
        let new = BatteryMood.of(r)
        let old = mood
        if new != old {
            mood = new
            onChange(old, new)
        }
    }

    /// The internal battery, if there is one.
    nonisolated static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  (d[kIOPSIsPresentKey] as? Bool) ?? true else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            let state = d[kIOPSPowerSourceStateKey] as? String
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            return BatteryReading(level: level, isCharging: charging, isPluggedIn: state == kIOPSACPowerValue)
        }
        return nil
    }
}
