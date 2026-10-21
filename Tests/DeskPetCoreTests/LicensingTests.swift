import Foundation
import Testing
@testable import DeskPetCore

@Suite struct LicensePolicyTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }
    func day(_ d: Int, hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }
    func record(validated: Date) -> LicenseRecord {
        LicenseRecord(key: "2b1f8e2d-c41e-4e8f-b2d3-d9fd61c38f43", instanceID: "lki_1", environment: .testMode,
                      activatedAt: validated, lastValidatedAt: validated)
    }

    @Test func trialCountsDownFourteenDaysThenEnds() {
        let start = day(1, hour: 23)
        #expect(LicensePolicy.access(trialStart: start, license: nil, now: day(1, hour: 23), calendar: cal) == .trial(daysLeft: 14))
        #expect(LicensePolicy.access(trialStart: start, license: nil, now: day(2, hour: 0), calendar: cal) == .trial(daysLeft: 13))
        #expect(LicensePolicy.access(trialStart: start, license: nil, now: day(14), calendar: cal) == .trial(daysLeft: 1))
        #expect(LicensePolicy.access(trialStart: start, license: nil, now: day(15), calendar: cal) == .trialEnded)
        #expect(LicensePolicy.access(trialStart: start, license: nil, now: day(30), calendar: cal) == .trialEnded)
    }

    @Test func clockSetBeforeTrialStartNeverGivesMoreThanFourteenDays() {
        #expect(LicensePolicy.trialDaysLeft(trialStart: day(10), now: day(1), calendar: cal) == 14)
    }

    @Test func licenseUnlocksUntilOfflineGraceRunsOut() {
        let r = record(validated: day(1))
        let now = day(1).addingTimeInterval(LicensePolicy.offlineGrace - 60)
        #expect(LicensePolicy.access(trialStart: day(1), license: r, now: now, calendar: cal) == .licensed)
        let later = day(1).addingTimeInterval(LicensePolicy.offlineGrace + 60)
        let access = LicensePolicy.access(trialStart: day(1), license: r, now: later, calendar: cal)
        #expect(access == .needsCheck)
        #expect(!access.unlocksPremium)
    }

    @Test func premiumUnlockedOnlyForTrialOrLicense() {
        #expect(LicenseAccess.licensed.unlocksPremium)
        #expect(LicenseAccess.trial(daysLeft: 1).unlocksPremium)
        #expect(!LicenseAccess.trialEnded.unlocksPremium)
    }

    @Test func revalidatesWeeklyOrWhenTheClockJumpsBack() {
        let r = record(validated: day(10))
        #expect(!LicensePolicy.needsRevalidation(r, now: day(12)))
        #expect(LicensePolicy.needsRevalidation(r, now: day(17, hour: 11)))
        #expect(LicensePolicy.needsRevalidation(r, now: day(9)))
    }

    @Test func pastedKeysAreCleanedUp() {
        #expect(LicensePolicy.normalizedKey("  \"ABCD-1234\"\n") == "ABCD-1234")
        #expect(LicensePolicy.normalizedKey("“ABCD-1234”") == "ABCD-1234")
    }

    @Test func maskedKeyShowsOnlyTheEnd() {
        #expect(record(validated: day(1)).maskedKey == "•••• 8f43")
    }

    @Test func recordRoundTripsThroughJSON() throws {
        let r = record(validated: day(3))
        let back = try JSONDecoder().decode(LicenseRecord.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }
}

/// Fake network for these tests only (separate from the Claude client's stub so suites can run in parallel).
final class LicenseStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(Int, String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: 4096); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
            Self.bodies.append(data)
        }
        let (code, body) = Self.responses.isEmpty ? (500, "{}") : Self.responses.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct DodoLicenseClientTests {
    func client(_ env: DodoEnvironment = .testMode, responses: [(Int, String)]) -> DodoLicenseClient {
        LicenseStub.responses = responses
        LicenseStub.requests = []
        LicenseStub.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseStub.self]
        return DodoLicenseClient(environment: env, session: URLSession(configuration: config))
    }

    func sentBody() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(LicenseStub.bodies.first))
    }

    let activated = #"{"id":"lki_123","business_id":"bus_1","name":"Mac","license_key_id":"lic_1","created_at":"2026-10-20T10:00:00Z","product":{"product_id":"pdt_1","name":"DeskPet"},"customer":{"customer_id":"cus_1","name":"A","email":"a@example.com"}}"#

    @Test func activateSendsKeyAndDeviceNameWithoutAnyAPIKey() async throws {
        let c = client(responses: [(201, activated)])
        let a = try await c.activate(key: "KEY-1", deviceName: "Studio Mac")
        #expect(a == .init(instanceID: "lki_123", productName: "DeskPet"))
        let req = try #require(LicenseStub.requests.first)
        #expect(req.url?.absoluteString == "https://test.dodopayments.com/licenses/activate")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "authorization") == nil)
        let body = try sentBody()
        #expect(body["license_key"]?.string == "KEY-1")
        #expect(body["name"]?.string == "Studio Mac")
    }

    @Test func liveModeUsesTheLiveHost() async throws {
        let c = client(.liveMode, responses: [(200, #"{"valid":true}"#)])
        _ = try await c.validate(key: "K", instanceID: "lki_1")
        #expect(LicenseStub.requests.first?.url?.absoluteString == "https://live.dodopayments.com/licenses/validate")
    }

    @Test func activationErrorsAreSpecific() async {
        await #expect(throws: LicenseError.notFound) { _ = try await client(responses: [(404, "{}")]).activate(key: "K", deviceName: "M") }
        await #expect(throws: LicenseError.inactive) { _ = try await client(responses: [(403, "{}")]).activate(key: "K", deviceName: "M") }
        await #expect(throws: LicenseError.activationLimitReached) { _ = try await client(responses: [(422, "{}")]).activate(key: "K", deviceName: "M") }
        await #expect(throws: LicenseError.server(500)) { _ = try await client(responses: [(500, "{}")]).activate(key: "K", deviceName: "M") }
        await #expect(throws: LicenseError.invalidResponse) { _ = try await client(responses: [(201, "{}")]).activate(key: "K", deviceName: "M") }
    }

    @Test func validateChecksThisMacsActivation() async throws {
        let c = client(responses: [(200, #"{"valid":true}"#)])
        #expect(try await c.validate(key: "K", instanceID: "lki_9"))
        #expect(try sentBody()["license_key_instance_id"]?.string == "lki_9")
        #expect(try await client(responses: [(200, #"{"valid":false}"#)]).validate(key: "K", instanceID: "lki_9") == false)
    }

    @Test func validateTreatsServerTroubleAsConnectivityNotRevocation() async {
        await #expect(throws: LicenseError.server(503)) { _ = try await client(responses: [(503, "{}")]).validate(key: "K", instanceID: "i") }
        await #expect(throws: LicenseError.invalidResponse) { _ = try await client(responses: [(200, "not json")]).validate(key: "K", instanceID: "i") }
        #expect(LicenseError.server(503).isConnectivity && LicenseError.offline.isConnectivity)
        #expect(!LicenseError.notFound.isConnectivity && !LicenseError.activationLimitReached.isConnectivity)
    }

    @Test func deactivateToleratesAnAlreadyRemovedActivation() async throws {
        try await client(responses: [(200, "")]).deactivate(key: "K", instanceID: "i")
        try await client(responses: [(403, "{}")]).deactivate(key: "K", instanceID: "i")
        let body = try sentBody()
        #expect(body["license_key"]?.string == "K" && body["license_key_instance_id"]?.string == "i")
        await #expect(throws: LicenseError.server(500)) { try await client(responses: [(500, "{}")]).deactivate(key: "K", instanceID: "i") }
    }
}
