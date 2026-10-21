import AppKit
import Combine
import DeskPetCore

/// Where the license and trial start date are kept. The app uses the Keychain;
/// the self-test uses memory so it never touches the real license.
@MainActor
protocol LicenseStorage {
    func loadRecord() -> LicenseRecord?
    func saveRecord(_ record: LicenseRecord?)
    func loadTrialStart() -> Date?
    func saveTrialStart(_ date: Date)
}

@MainActor
struct KeychainLicenseStorage: LicenseStorage {
    func loadRecord() -> LicenseRecord? {
        KeychainStore.loadLicenseData(account: "license").flatMap { try? JSONDecoder().decode(LicenseRecord.self, from: $0) }
    }

    func saveRecord(_ record: LicenseRecord?) {
        if let record, let data = try? JSONEncoder().encode(record) {
            try? KeychainStore.saveLicenseData(data, account: "license")
        } else {
            KeychainStore.deleteLicenseData(account: "license")
        }
    }

    func loadTrialStart() -> Date? {
        KeychainStore.loadLicenseData(account: "trial-start")
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
    }

    func saveTrialStart(_ date: Date) {
        try? KeychainStore.saveLicenseData(Data(String(date.timeIntervalSince1970).utf8), account: "trial-start")
    }
}

@MainActor
final class InMemoryLicenseStorage: LicenseStorage {
    var record: LicenseRecord?
    var trialStart: Date?
    init(record: LicenseRecord? = nil, trialStart: Date? = nil) {
        self.record = record
        self.trialStart = trialStart
    }
    func loadRecord() -> LicenseRecord? { record }
    func saveRecord(_ record: LicenseRecord?) { self.record = record }
    func loadTrialStart() -> Date? { trialStart }
    func saveTrialStart(_ date: Date) { trialStart = date }
}

/// The 14-day trial and the Dodo Payments license for this Mac.
///
/// Network use: only when the user activates/deactivates a key, plus a
/// re-check of an activated key about once a week. Nothing is sent during the
/// trial or without a key.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var access: LicenseAccess = .trial(daysLeft: LicensePolicy.trialDays)
    @Published private(set) var record: LicenseRecord?
    @Published private(set) var isWorking = false
    /// Result of the last activate/deactivate/check, shown in Settings › License.
    @Published var status: (ok: Bool, text: String)?

    let environment: DodoEnvironment
    let buyURL: URL
    private let storage: LicenseStorage
    private let client: DodoLicenseClient
    private let calendar: Calendar
    private let now: () -> Date
    private let trialStart: Date
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    /// Called when someone tries a premium feature that's locked.
    var onLocked: (PremiumFeature) -> Void = { _ in }

    init(storage: LicenseStorage, environment: DodoEnvironment, buyURL: URL,
         session: URLSession = .shared, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.environment = environment
        self.buyURL = buyURL
        self.client = DodoLicenseClient(environment: environment, session: session)
        self.calendar = calendar
        self.now = now

        if let saved = storage.loadTrialStart() {
            trialStart = saved
        } else {
            trialStart = now()
            storage.saveTrialStart(trialStart)
        }
        // A key from the other environment (e.g. a test key in a live build) can't be checked.
        if let saved = storage.loadRecord(), saved.environment == environment {
            record = saved
        } else if storage.loadRecord() != nil {
            storage.saveRecord(nil)
        }
        refresh()
    }

    /// Build settings from Info.plist (set by scripts/build-app.sh).
    static func fromBundle(storage: LicenseStorage? = nil) -> LicenseManager {
        let info = Bundle.main.infoDictionary ?? [:]
        let env = (info["DPDodoEnvironment"] as? String).flatMap(DodoEnvironment.init(rawValue:)) ?? .testMode
        let buy = (info["DPBuyURL"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://deskpet.app")!
        return LicenseManager(storage: storage ?? KeychainLicenseStorage(), environment: env, buyURL: buy)
    }

    /// Re-check on launch, every few hours, and after the Mac wakes.
    func start() {
        Task { await revalidateIfNeeded() }
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                Task { await self?.revalidateIfNeeded() }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let next = LicensePolicy.access(trialStart: trialStart, license: record, now: now(), calendar: calendar)
        if next != access { access = next }
    }

    // MARK: Gate

    /// True if the feature may be used now; otherwise reports it via `onLocked`.
    func allows(_ feature: PremiumFeature) -> Bool {
        guard lockedReason(feature) != nil else { return true }
        onLocked(feature)
        return false
    }

    /// Nil when the feature is available; otherwise why not, in the pet's voice.
    func lockedReason(_ feature: PremiumFeature) -> String? {
        refresh()
        return access.unlocksPremium ? nil : lockedMessage(for: feature)
    }

    private func lockedMessage(for feature: PremiumFeature) -> String {
        switch access {
        case .needsCheck:
            return "\(feature.title) needs a quick license check. Connect to the internet, then open Settings › License."
        default:
            return "Your free trial has ended. \(feature.title) is part of DeskPet Full: buy once at \(buyURL.host ?? "deskpet.app"), then add your key in Settings › License."
        }
    }

    // MARK: Actions

    func activate(_ rawKey: String) async {
        let key = LicensePolicy.normalizedKey(rawKey)
        guard key.count >= 8 else {
            status = (false, "That doesn’t look like a license key.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let activation = try await client.activate(key: key, deviceName: Self.deviceName)
            let t = now()
            let r = LicenseRecord(key: key, instanceID: activation.instanceID, environment: environment,
                                  activatedAt: t, lastValidatedAt: t)
            storage.saveRecord(r)
            record = r
            refresh()
            status = (true, "Activated. Thank you for supporting DeskPet!")
        } catch {
            status = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Frees this Mac's slot so the key can be used on another Mac.
    func deactivate() async {
        guard let r = record else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.deactivate(key: r.key, instanceID: r.instanceID)
            storage.saveRecord(nil)
            record = nil
            refresh()
            status = (true, "Deactivated on this Mac. You can now use the key on another Mac.")
        } catch {
            status = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Asks Dodo whether the key is still good (forced from Settings, otherwise weekly).
    func revalidateIfNeeded(force: Bool = false) async {
        guard let r = record, force || LicensePolicy.needsRevalidation(r, now: now()), !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if try await client.validate(key: r.key, instanceID: r.instanceID) {
                var updated = r
                updated.lastValidatedAt = now()
                storage.saveRecord(updated)
                record = updated
                if force { status = (true, "License confirmed.") }
            } else {
                // A real answer from Dodo: revoked, refunded, or deactivated elsewhere.
                storage.saveRecord(nil)
                record = nil
                status = (false, "This license is no longer active on this Mac. If that’s unexpected, enter your key again or contact support.")
            }
        } catch {
            // Offline or server trouble: keep working within the grace period.
            if force { status = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription) }
        }
        refresh()
    }

    func openBuyPage() { NSWorkspace.shared.open(buyURL) }

    /// Shown in the customer's list of activated Macs.
    static var deviceName: String {
        let name = Host.current().localizedName ?? "Mac"
        return String("\(name) · DeskPet".prefix(100))
    }
}
