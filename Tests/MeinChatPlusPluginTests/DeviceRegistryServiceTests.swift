import Testing
import Foundation
@testable import MeinChatPlusPlugin

/// Sprint S28.7 §4.3 + §3.1 — Device registry HTTP wrappers.
struct DeviceRegistryServiceTests {

    @Test
    func listMyDevicesHitsCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubGet("/me/devices", json: """
        { "devices": [
            { "id": "d1", "user_id": "u1", "label": "iPhone", "identity_key": "key1", "created_at": "2026-05-29T10:00:00Z" }
          ]
        }
        """)
        let svc = DefaultDeviceRegistryService(api: api)
        let devices = try await svc.listMyDevices()
        #expect(devices.count == 1)
        #expect(devices[0].id == "d1")
        #expect(devices[0].label == "iPhone")
        #expect(api.recordedRequests == [.get(path: "/me/devices")])
    }

    @Test
    func registerDevicePostsToCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubPost("/me/devices", json: """
        { "id": "d2", "user_id": "u1", "label": "iPad", "identity_key": "k", "created_at": null }
        """)
        let svc = DefaultDeviceRegistryService(api: api)
        let d = try await svc.registerDevice(label: "iPad", identityKey: "k")
        #expect(d.id == "d2")
        #expect(d.label == "iPad")
        // The request body must contain the label + identity_key we sent.
        if case let .post(path, body) = api.recordedRequests[0] {
            #expect(path == "/me/devices")
            let json = String(data: body ?? Data(), encoding: .utf8) ?? ""
            #expect(json.contains("iPad"))
            #expect(json.contains("identity_key"))
        } else {
            Issue.record("Expected POST, got \(api.recordedRequests[0])")
        }
    }

    @Test
    func revokeDeviceHitsCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubDelete("/me/devices/d3")
        let svc = DefaultDeviceRegistryService(api: api)
        try await svc.revokeDevice(id: "d3")
        #expect(api.recordedRequests == [.delete(path: "/me/devices/d3")])
    }

    @Test
    func listPeerDevicesHitsCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubGet("/messaging/users/u-peer/devices", json: """
        { "devices": [] }
        """)
        let svc = DefaultDeviceRegistryService(api: api)
        let devices = try await svc.listPeerDevices(userId: "u-peer")
        #expect(devices.isEmpty)
        #expect(api.recordedRequests == [.get(path: "/messaging/users/u-peer/devices")])
    }

    @Test
    func fetchBundleHitsCorrectPath() async throws {
        let api = MockAPIClient()
        api.stubGet("/messaging/users/u-peer/devices/d-peer/bundle", json: """
        {
          "device_id": "d-peer",
          "identity_key": "ik",
          "signed_prekey": { "id": 1, "public_key": "sp", "signature": "sig", "created_at": null },
          "one_time_prekey": { "id": 7, "public_key": "ot" }
        }
        """)
        let svc = DefaultDeviceRegistryService(api: api)
        let bundle = try await svc.fetchBundle(userId: "u-peer", deviceId: "d-peer")
        #expect(bundle.deviceId == "d-peer")
        #expect(bundle.identityKey == "ik")
        #expect(bundle.signedPrekey.id == 1)
        #expect(bundle.oneTimePrekey?.id == 7)
    }

    @Test
    func fetchBundleHandlesMissingOneTimePrekey() async throws {
        let api = MockAPIClient()
        api.stubGet("/messaging/users/u-peer/devices/d-peer/bundle", json: """
        {
          "device_id": "d-peer",
          "identity_key": "ik",
          "signed_prekey": { "id": 1, "public_key": "sp", "signature": "sig", "created_at": null },
          "one_time_prekey": null
        }
        """)
        let svc = DefaultDeviceRegistryService(api: api)
        let bundle = try await svc.fetchBundle(userId: "u-peer", deviceId: "d-peer")
        #expect(bundle.oneTimePrekey == nil)
    }
}
