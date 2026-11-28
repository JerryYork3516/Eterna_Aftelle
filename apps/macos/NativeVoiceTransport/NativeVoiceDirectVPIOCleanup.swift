#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
@preconcurrency import AudioToolbox
#if NATIVE_VOICE_DIRECT_VPIO
@preconcurrency import AVFoundation
#endif
import os

/// Carries a unit's teardown results from serialized transport control to the lab, including startup rollback.
final nonisolated class NativeVoiceDirectVPIOCleanup: Sendable {
    struct ListenerResult: Encodable, Equatable, Sendable {
        let property: AudioUnitPropertyID
        let status: OSStatus
    }

    struct Report: Encodable, Equatable, Sendable {
        let stop: OSStatus?
        let removePropertyListeners: [ListenerResult]
        let uninitialize: OSStatus?
        let dispose: OSStatus

        var failed: Bool {
            (stop ?? noErr) != noErr || (uninitialize ?? noErr) != noErr || dispose != noErr
                || removePropertyListeners.contains { $0.status != noErr }
        }

        func outcome(after sessionOutcome: String) -> String {
            failed ? "cleanup_failed" : sessionOutcome
        }

        var detail: String {
            let listeners = removePropertyListeners.map { "\($0.property)=\($0.status)" }.joined(separator: ", ")
            return [
                failed ? "Direct VPIO cleanup_failed" : "Direct VPIO cleanup",
                "AudioOutputUnitStop: \(stop.map(String.init) ?? "not_attempted")",
                "AudioUnitRemovePropertyListenerWithUserData: \(listeners.isEmpty ? "not_attempted" : listeners)",
                "AudioUnitUninitialize: \(uninitialize.map(String.init) ?? "not_attempted")",
                "AudioComponentInstanceDispose: \(dispose)"
            ].joined(separator: "\n")
        }
    }

    private let saved = OSAllocatedUnfairLock<Report?>(initialState: nil)

    var report: Report? {
        saved.withLock { $0 }
    }

    #if NATIVE_VOICE_DIRECT_VPIO
    func release(
        _ unit: AudioUnit, api: NativeVoiceDirectVPIO.UnitAPI, callbacks: OpaquePointer?,
        watched: [AudioUnitPropertyID], phase: (startAttempted: Bool, initialized: Bool)
    ) -> Report {
        let stop = phase.startAttempted ? api.stop(unit) : nil
        let listeners: [ListenerResult] = callbacks.map { context in
            watched.reversed().map { property in
                .init(property: property,
                      status: api.unlisten(unit, property, nvt_direct_vpio_changed, UnsafeMutableRawPointer(context)))
            }
        } ?? []
        let uninitialize = phase.initialized ? api.uninitialize(unit) : nil
        let report = Report(
            stop: stop, removePropertyListeners: listeners, uninitialize: uninitialize, dispose: api.dispose(unit)
        )
        saved.withLock { $0 = report }
        return report
    }
    #endif
}

#if NATIVE_VOICE_DIRECT_VPIO
extension AppleNativeVoiceTransport {
    static func directVPIO(limits: Limits, cleanup: NativeVoiceDirectVPIOCleanup) -> AppleNativeVoiceTransport {
        AppleNativeVoiceTransport(
            makeEngine: { NativeVoiceDirectVPIO(callbackLimit: limits.callbackFrames, cleanup: cleanup) },
            authorized: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
            limits: limits
        )
    }
}
#endif
#endif
