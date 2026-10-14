import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore

/// Register/remove/check belong to one control caller; notification delivery may be concurrent.
final class ConfigurationChangeObserver: PlaybackConfigurationObserving {
    private let center: NotificationCenter
    private let observedObject: AnyObject
    private let recorder: RecorderOwner
    private var token: NSObjectProtocol?
    private var registrationAttempted = false

    init(observedObject: AnyObject, recorder: RecorderOwner, center: NotificationCenter = .default) {
        self.observedObject = observedObject
        self.recorder = recorder
        self.center = center
    }

    func register() throws {
        guard !registrationAttempted else {
            throw EngineeringFailure(stage: .vpConfiguration, code: .prePlaybackConfigurationInvalid)
        }
        registrationAttempted = true
        let recorder = recorder
        token = center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: observedObject, queue: nil
        ) { _ in
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_FORMAT))
        }
    }

    func check() throws {
        if vp_recorder_snapshot(recorder.handle).invalid_reasons & UInt32(VP_INVALID_FORMAT) != 0 {
            throw EngineeringFailure(stage: .vpConfiguration, code: .prePlaybackConfigurationInvalid)
        }
    }

    func remove() {
        guard let token else { return }
        self.token = nil
        center.removeObserver(token)
    }
}
