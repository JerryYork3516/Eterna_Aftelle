import Foundation

nonisolated final class MacSpeechWebRTCAECProcessor:
    MacSpeechAECBackend, @unchecked Sendable
{
    private var bridge: OpaquePointer?

    deinit {
        AftelleAECBridgeDestroy(bridge)
    }

    func configure() throws {
        if bridge == nil {
            try requireSuccess(AftelleAECBridgeCreate(&bridge), .createFailed)
        }
        guard let bridge else { throw MacSpeechAECBackendError.createFailed }
        try requireSuccess(
            AftelleAECBridgeConfigure(
                bridge,
                Int32(MacSpeechAcousticEchoHost.sampleRate),
                1,
                MacSpeechAcousticEchoHost.frameSampleCount
            ),
            .configureFailed
        )
    }

    func processRender(_ samples: [Float]) throws {
        guard let bridge else { throw MacSpeechAECBackendError.renderFailed }
        try requireFrame(samples)
        try samples.withUnsafeBufferPointer { input in
            try requireSuccess(
                AftelleAECBridgeProcessRender(
                    bridge,
                    input.baseAddress,
                    input.count
                ),
                .renderFailed
            )
        }
    }

    func processCapture(_ samples: [Float]) throws -> [Float] {
        guard let bridge else { throw MacSpeechAECBackendError.captureFailed }
        try requireFrame(samples)
        var output = [Float](
            repeating: 0,
            count: MacSpeechAcousticEchoHost.frameSampleCount
        )
        try samples.withUnsafeBufferPointer { input in
            try output.withUnsafeMutableBufferPointer { destination in
                try requireSuccess(
                    AftelleAECBridgeProcessCapture(
                        bridge,
                        input.baseAddress,
                        destination.baseAddress,
                        input.count
                    ),
                    .captureFailed
                )
            }
        }
        return output
    }

    func setDelay(milliseconds: Int) throws {
        guard let bridge else { throw MacSpeechAECBackendError.delayFailed }
        try requireSuccess(
            AftelleAECBridgeSetDelayMs(bridge, Int32(milliseconds)),
            .delayFailed
        )
    }

    func reset() throws {
        guard let bridge else { throw MacSpeechAECBackendError.resetFailed }
        try requireSuccess(
            AftelleAECBridgeReset(bridge),
            .resetFailed
        )
    }

    func stats() throws -> MacSpeechAECBackendStats {
        guard let bridge else { throw MacSpeechAECBackendError.statsFailed }
        var stats = AftelleAECBridgeStats()
        try requireSuccess(
            AftelleAECBridgeGetStats(bridge, &stats),
            .statsFailed
        )
        return MacSpeechAECBackendStats(
            enabled: stats.enabled != 0,
            active: stats.active != 0,
            estimatedDelayMilliseconds: Int(stats.estimated_delay_ms),
            erlDecibels: stats.erl_db,
            erleDecibels: stats.erle_db
        )
    }

    private func requireFrame(_ samples: [Float]) throws {
        guard samples.count == MacSpeechAcousticEchoHost.frameSampleCount else {
            throw MacSpeechAECBackendError.captureFailed
        }
    }

    private func requireSuccess(
        _ result: AftelleAECBridgeError,
        _ error: MacSpeechAECBackendError
    ) throws {
        guard result == AFTELLE_AEC_BRIDGE_OK else { throw error }
    }
}
