import Foundation

nonisolated enum NativeVoiceSessionError: Error {
    case permission, state, format, route, voiceProcessing
}

nonisolated struct NativeVoiceIOFormat: Equatable, Sendable {
    let sampleRate: Double
    let channels: UInt32
    let interleaved: Bool
    let float32: Bool

    var supported: Bool {
        sampleRate.isFinite && sampleRate > 0 && channels > 0 && float32
    }
}

nonisolated struct NativeVoiceGraphPlan: Equatable, Sendable {
    let capture: NativeVoiceIOFormat
    let render: NativeVoiceIOFormat

    var source: NativeVoiceIOFormat {
        NativeVoiceIOFormat(sampleRate: render.sampleRate, channels: 1, interleaved: false, float32: true)
    }
}

nonisolated struct NativeVoiceDeviceBinding: Equatable, Sendable {
    let id: UInt32
    let uid: String
    let nominalRate: Double
    let inputStreams: [UInt32]
    let outputStreams: [UInt32]
    let inputChannels: [UInt32]
    let outputChannels: [UInt32]
    let aggregateUIDs: [String]?
    let activeMembers: [UInt32]
    let clockMemberUID: String?
}

nonisolated struct NativeVoiceGraphSnapshot: Equatable, Sendable {
    let plan: NativeVoiceGraphPlan
    let inputDevice: UInt32
    let outputDevice: UInt32
    let bindings: [NativeVoiceDeviceBinding]
}

/// Owns the preallocated C context. The node blocks lease the same allocation.
final nonisolated class NativeVoiceCallbackLease: @unchecked Sendable {
    let factory: NVTRTLease

    init?(config: NVTRTConfig) {
        guard let factory = NVTRTLease(config: config) else { return nil }
        self.factory = factory
    }

    var context: OpaquePointer {
        factory.io
    }

    func close() {
        nvt_rt_close(context)
    }
}

/// Invoked only by session control. Fake implementations use the same graph plan and C endpoints.
nonisolated protocol NativeVoiceGraphBackend: AnyObject {
    func negotiate() throws -> NativeVoiceGraphPlan
    func install(
        _ plan: NativeVoiceGraphPlan,
        lease: NativeVoiceCallbackLease,
        configurationChanged: @escaping @Sendable () -> Void
    ) throws
    func start() throws
    func snapshot() throws -> NativeVoiceGraphSnapshot
    func watchDevices(_ snapshot: NativeVoiceGraphSnapshot, changed: @escaping @Sendable () -> Void) throws
    func stop()
}
