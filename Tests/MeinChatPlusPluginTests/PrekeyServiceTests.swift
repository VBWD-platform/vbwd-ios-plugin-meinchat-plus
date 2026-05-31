import Testing
import Foundation
@testable import MeinChatPlusPlugin

/// Sprint S28.7 §4.3 + §3.5 — Prekey service specs.
struct PrekeyServiceTests {

    private func makeStatus(remaining: Int, capacity: Int, lowWater: Int? = nil) -> String {
        var fields: [String] = [
            "\"one_time_remaining\": \(remaining)",
            "\"one_time_capacity\": \(capacity)",
            "\"signed_rotated_at\": null",
        ]
        if let lowWater {
            fields.append("\"low_water_mark\": \(lowWater)")
        } else {
            fields.append("\"low_water_mark\": null")
        }
        return "{\(fields.joined(separator: ","))}"
    }

    @Test
    func fetchStatusHitsCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubGet("/me/prekeys/status",
                    json: makeStatus(remaining: 97, capacity: 100, lowWater: 20))
        let svc = DefaultPrekeyService(api: api)

        let status = try await svc.fetchStatus()
        #expect(status.oneTimeRemaining == 97)
        #expect(status.oneTimeCapacity == 100)
        #expect(status.lowWaterMark == 20)
        #expect(api.recordedRequests == [.get(path: "/me/prekeys/status")])
    }

    @Test
    func needsRefillUsesServerLowWaterWhenPresent() async throws {
        let api = MockAPIClient()
        api.stubGet("/me/prekeys/status",
                    json: makeStatus(remaining: 20, capacity: 100, lowWater: 20))
        let svc = DefaultPrekeyService(api: api)
        #expect(try await svc.needsRefill() == true)
    }

    @Test
    func needsRefillFalseAboveLowWaterMark() async throws {
        let api = MockAPIClient()
        api.stubGet("/me/prekeys/status",
                    json: makeStatus(remaining: 21, capacity: 100, lowWater: 20))
        let svc = DefaultPrekeyService(api: api)
        #expect(try await svc.needsRefill() == false)
    }

    @Test
    func needsRefillFallbackFraction() async throws {
        // No low-water mark from server → fall back to 20% of capacity (= 20).
        let api = MockAPIClient()
        api.stubGet("/me/prekeys/status",
                    json: makeStatus(remaining: 20, capacity: 100, lowWater: nil))
        let svc = DefaultPrekeyService(api: api, fallbackLowWaterFraction: 0.2)
        #expect(try await svc.needsRefill() == true)
    }

    @Test
    func publishOneTimeNoOpOnEmptyBatch() async throws {
        let api = MockAPIClient()
        let svc = DefaultPrekeyService(api: api)
        try await svc.publishOneTimeBatch([])
        #expect(api.recordedRequests.isEmpty)
    }

    @Test
    func publishOneTimeHitsCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubPost("/me/prekeys/one-time", json: "{}")
        let svc = DefaultPrekeyService(api: api)
        try await svc.publishOneTimeBatch([
            OneTimePrekey(id: 1, publicKey: "key1"),
            OneTimePrekey(id: 2, publicKey: "key2"),
        ])
        #expect(api.recordedRequests.count == 1)
        if case let .post(path, _) = api.recordedRequests[0] {
            #expect(path == "/me/prekeys/one-time")
        } else {
            Issue.record("Expected POST, got \(api.recordedRequests[0])")
        }
    }

    @Test
    func publishSignedHitsCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubPost("/me/prekeys/signed", json: "{}")
        let svc = DefaultPrekeyService(api: api)
        try await svc.publishSigned(SignedPrekey(
            id: 1, publicKey: "pk", signature: "sig", createdAt: nil))
        if case let .post(path, _) = api.recordedRequests[0] {
            #expect(path == "/me/prekeys/signed")
        } else {
            Issue.record("Expected POST, got \(api.recordedRequests[0])")
        }
    }
}
