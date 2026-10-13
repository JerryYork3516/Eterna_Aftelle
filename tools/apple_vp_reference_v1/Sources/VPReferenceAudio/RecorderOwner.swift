import Foundation
import VPRecorder
import VPReferenceCore

final class RecorderOwner {
    let handle: OpaquePointer
    private var sealAttempted = false
    private var sealSucceeded = false

    init(configuration: RunConfiguration) throws {
        var settings = vp_recorder_default_config()
        var errorCode: Int32 = 0
        let recorder = configuration.outputDirectory.path.withCString { path in
            vp_recorder_create(path, &settings, &errorCode)
        }
        guard let recorder else { throw AudioReferenceError.recorderUnavailable }
        handle = recorder
    }

    func seal() {
        if !sealAttempted {
            sealAttempted = true
            sealSucceeded = vp_recorder_seal(handle)
        }
    }

    func outcome(directory: URL, expectsRender: Bool) -> AudioRunOutcome {
        let evidence = directory.appendingPathComponent("evidence.vp0")
        let validation = evidence.path.withCString { vp_recorder_validate_file($0) }
        return AudioRunOutcome(
            snapshot: vp_recorder_snapshot(handle), file: validation,
            expectsRender: expectsRender, controlSealSucceeded: sealSucceeded
        )
    }

    deinit {
        vp_recorder_destroy(handle)
    }
}
