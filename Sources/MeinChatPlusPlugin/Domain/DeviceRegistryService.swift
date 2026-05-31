import Foundation
import VBWDCore

/// Wraps `/me/devices` and the peer-device lookup routes (S28.3b §2.1).
/// Stateless — caller holds any local device-id reference.
public protocol DeviceRegistryServiceProtocol: Sendable {
    func listMyDevices() async throws -> [DeviceDescriptor]
    func registerDevice(label: String, identityKey: String) async throws -> DeviceDescriptor
    func revokeDevice(id: String) async throws
    func listPeerDevices(userId: String) async throws -> [DeviceDescriptor]
    func fetchBundle(userId: String, deviceId: String) async throws -> PrekeyBundle
}

public final class DefaultDeviceRegistryService: DeviceRegistryServiceProtocol, @unchecked Sendable {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }

    private struct DeviceListResponse: Codable { let devices: [DeviceDescriptor]? }
    private struct RegisterBody: Encodable { let label: String; let identity_key: String }

    public func listMyDevices() async throws -> [DeviceDescriptor] {
        let resp: DeviceListResponse = try await api.get(MeinChatPlusEndpoints.myDevices)
        return resp.devices ?? []
    }

    public func registerDevice(label: String, identityKey: String) async throws -> DeviceDescriptor {
        let device: DeviceDescriptor = try await api.post(
            MeinChatPlusEndpoints.myDevices,
            body: RegisterBody(label: label, identity_key: identityKey))
        return device
    }

    public func revokeDevice(id: String) async throws {
        let _: EmptyResponse = try await api.delete(MeinChatPlusEndpoints.device(id: id))
    }

    public func listPeerDevices(userId: String) async throws -> [DeviceDescriptor] {
        let resp: DeviceListResponse = try await api.get(
            MeinChatPlusEndpoints.userDevices(userId: userId))
        return resp.devices ?? []
    }

    public func fetchBundle(userId: String, deviceId: String) async throws -> PrekeyBundle {
        try await api.get(MeinChatPlusEndpoints.bundle(userId: userId, deviceId: deviceId))
    }
}
