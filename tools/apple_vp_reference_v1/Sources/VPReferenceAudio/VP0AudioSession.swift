import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore

public final class VP0AudioSession {
    private var used = false

    public init() {}

    public func run(configuration: RunConfiguration) throws -> AudioRunOutcome {
        try EngineeringFailure.check(stage: .command, code: .invalidArguments) {
            try configuration.validateForAudio()
        }
        guard !used else { throw EngineeringFailure(stage: .recorder, code: .sessionAlreadyUsed) }
        used = true
        try MicrophonePermissionPlan.requireAuthorized(status: MicrophonePermissionAccess.currentStatus())
        let material = try EngineeringFailure.check(stage: .sourceMaterial, code: .materialLoadFailed) {
            try configuration.materialURL.map(PCMSourceMaterial.load)
        }
        let driver = AppleEngineDriver(material: material?.buffer)
        let configured = try ConfigurationPlan.configure(mode: configuration.mode, driver: driver)
        let route = try readRoute(driver: driver)
        var manifest = try EngineeringFailure.check(stage: .evidenceWrite, code: .identityFailed) {
            try AudioRunManifest.create(
                configuration: configuration, configured: configured, route: route, driver: driver, material: material
            )
        }
        let recorder = try EngineeringFailure.check(stage: .recorder, code: .recorderCreateFailed) {
            try RecorderOwner(configuration: configuration)
        }
        do {
            try EngineeringFailure.check(stage: .evidenceWrite, code: .preparedWriteFailed) {
                try manifest.writePrepared(directory: configuration.outputDirectory)
            }
            guard route.deviceBindingStatus == "NODE_IDS_MATCH_DEFAULTS" else {
                throw EngineeringFailure(stage: .deviceBinding, code: .deviceBindingMismatch)
            }
            try capture(configuration: configuration, driver: driver, recorder: recorder, manifest: &manifest)
            try observeAfterStop(driver: driver, manifest: &manifest)
        } catch {
            manifest.diagnostics.record(EngineeringFailure.capture(error, stage: .recorder, code: .recorderInvalid))
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
        }
        return try finish(configuration: configuration, recorder: recorder, manifest: &manifest)
    }

    private func capture(
        configuration: RunConfiguration, driver: AppleEngineDriver, recorder: RecorderOwner,
        manifest: inout AudioRunManifest
    ) throws {
        installTaps(driver: driver, recorder: recorder)
        var observer: NSObjectProtocol?
        let startTick = vp_recorder_now_tick()
        try PlaybackLifecycle.run(
            startAndValidate: {
                guard vp_recorder_arm(recorder.handle, startTick) else {
                    throw EngineeringFailure(stage: .recorder, code: .recorderArmFailed)
                }
                try startAndWait(driver: driver)
                try observeRunning(driver: driver, manifest: &manifest)
                observer = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange, object: driver.engine, queue: nil
                ) { _ in vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_FORMAT)) }
                if vp_recorder_snapshot(recorder.handle).invalid_reasons & UInt32(VP_INVALID_FORMAT) != 0 {
                    throw EngineeringFailure(stage: .vpConfiguration, code: .prePlaybackConfigurationInvalid)
                }
            },
            play: { driver.player.play() },
            score: { wait(configuration: configuration, recorder: recorder, startTick: startTick) },
            stop: { stop(driver: driver, observer: observer) }
        )
    }

    private func startAndWait(driver: AppleEngineDriver) throws {
        driver.schedulePlayback()
        try EngineeringFailure.check(stage: .enginePrepare, code: .enginePrepareFailed) {
            guard !driver.engine.isRunning else {
                throw EngineeringFailure(stage: .enginePrepare, code: .engineAlreadyRunning)
            }
            driver.engine.prepare()
        }
        try EngineeringFailure.check(stage: .engineStart, code: .engineStartFailed) {
            try driver.engine.start()
        }
    }

    private func wait(configuration: RunConfiguration, recorder: RecorderOwner, startTick: UInt64) {
        DiagnosticLifecycle.finishWindow(
            durationSeconds: configuration.durationSeconds,
            elapsedSeconds: {
                Double(vp_recorder_now_tick() - startTick) / Double(vp_recorder_ticks_for_seconds(1))
            },
            observe: {},
            onFailure: { _ in vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_WRITE)) },
            wait: { Thread.sleep(forTimeInterval: $0) }
        )
    }

    private func stop(driver: AppleEngineDriver, observer: NSObjectProtocol?) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        driver.player.stop()
        driver.engine.stop()
        driver.engine.inputNode.removeTap(onBus: 0)
        driver.engine.mainMixerNode.removeTap(onBus: 0)
    }

    private func installTaps(driver: AppleEngineDriver, recorder: RecorderOwner) {
        NativePCMTap.install(node: driver.engine.inputNode, stream: UInt32(VP_STREAM_INPUT), recorder: recorder)
        NativePCMTap.install(node: driver.engine.mainMixerNode, stream: UInt32(VP_STREAM_RENDER), recorder: recorder)
    }

    private func readRoute(driver: AppleEngineDriver) throws -> AudioRouteSnapshot {
        try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.read(engine: driver.engine)
        }
    }

    private func observeAfterStop(driver: AppleEngineDriver, manifest: inout AudioRunManifest) throws {
        manifest.postStopRoute = try readRoute(driver: driver)
        manifest.postStopFormats = try EngineeringFailure.check(stage: .vpConfiguration, code: .formatReadFailed) {
            try driver.readFormats()
        }
        manifest.postStopState = try EngineeringFailure.check(stage: .vpState, code: .stateReadFailed) {
            try driver.readVoiceProcessingState()
        }
        manifest.postStopHardwareOutputFormat = AppleEngineDriver.snapshot(
            driver.engine.outputNode.outputFormat(forBus: 0))
        guard manifest.postStopRoute == manifest.routeBefore else {
            throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
        }
    }

    private func observeRunning(driver: AppleEngineDriver, manifest: inout AudioRunManifest) throws {
        let state = try EngineeringFailure.check(stage: .vpState, code: .stateReadFailed) {
            try driver.readVoiceProcessingState()
        }
        manifest.runningState = state
        let formats = try EngineeringFailure.check(stage: .vpConfiguration, code: .formatReadFailed) {
            try driver.readFormats()
        }
        manifest.runningFormats = formats
        let hardwareOutput = AppleEngineDriver.snapshot(driver.engine.outputNode.outputFormat(forBus: 0))
        manifest.runningHardwareOutputFormat = hardwareOutput
        try RunningConfigurationPlan.validate(
            configured: manifest.configured, expectedHardwareOutput: manifest.hardwareOutputFormat,
            actual: RunningConfigurationSnapshot(state: state, formats: formats, hardwareOutput: hardwareOutput)
        )
        manifest.terminalStatus = "RUNNING"
    }

    private func finish(
        configuration: RunConfiguration, recorder: RecorderOwner, manifest: inout AudioRunManifest
    ) throws -> AudioRunOutcome {
        if !recorder.seal() {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .seal, code: .sealFailed))
        }
        let outcome = recorder.outcome(
            directory: configuration.outputDirectory, expectsRender: configuration.materialURL != nil)
        if !outcome.isCompleteForReference, manifest.diagnostics.primary == nil {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .recorder, code: .recorderInvalid))
        }
        manifest.outcome = outcome
        manifest.terminalStatus = manifest.diagnostics.primary == nil ? outcome.status : "INVALID"
        do {
            try manifest.writeFinal(directory: configuration.outputDirectory)
        } catch {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .evidenceWrite, code: .finalWriteFailed))
        }
        if manifest.diagnostics.primary != nil { throw EngineeringFailure(diagnostics: manifest.diagnostics) }
        return outcome
    }
}
