import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore

public final class VP0AudioSession {
    private var used = false

    public init() {}

    public func run(configuration: RunConfiguration) throws -> AudioRunOutcome {
        try run(configuration: configuration, vpa: nil)
    }

    func runVPA(request: VPARequest) throws -> AudioRunOutcome {
        try request.validate()
        return try run(configuration: request.configuration, vpa: request)
    }

    private func run(configuration: RunConfiguration, vpa: VPARequest?) throws -> AudioRunOutcome {
        try EngineeringFailure.check(stage: .command, code: .invalidArguments) {
            try configuration.validateForAudio()
        }
        guard !used else { throw EngineeringFailure(stage: .recorder, code: .sessionAlreadyUsed) }
        used = true
        try MicrophonePermissionPlan.requireAuthorized(status: MicrophonePermissionAccess.currentStatus())
        let material = try EngineeringFailure.check(stage: .sourceMaterial, code: .materialLoadFailed) {
            try configuration.materialURL.map(PCMSourceMaterial.load)
        }
        let admission = try vpa.map { try VPAAdmission.prepare(request: $0, material: material) }
        let driver = AppleEngineDriver(material: material?.buffer)
        let configured = try ConfigurationPlan.configure(mode: configuration.mode, driver: driver)
        let route = try readRoute(driver: driver)
        var manifest = try EngineeringFailure.check(stage: .evidenceWrite, code: .identityFailed) {
            try AudioRunManifest.create(
                configuration: configuration, configured: configured, route: route, driver: driver, material: material
            )
        }
        if let admission {
            manifest.prepareVPA(registrationSHA256: admission.registrationSHA256)
        }
        let recorder = try EngineeringFailure.check(stage: .recorder, code: .recorderCreateFailed) {
            try RecorderOwner(configuration: configuration, maximumSeconds: vpa == nil ? 60 : VPARequest.maximumSeconds)
        }
        do {
            try EngineeringFailure.check(stage: .evidenceWrite, code: .preparedWriteFailed) {
                try manifest.writePrepared(directory: configuration.outputDirectory)
            }
            if let admission {
                try admission.validateRoute(route)
            } else {
                guard route.hasVerifiedBinding else {
                    throw EngineeringFailure(stage: .deviceBinding, code: .deviceBindingMismatch)
                }
            }
            try capture(
                configuration: configuration, driver: driver, recorder: recorder, admission: admission,
                manifest: &manifest)
            try observeAfterStop(driver: driver, manifest: &manifest)
            if let admission {
                try validateVPA(driver: driver, manifest: &manifest, admission: admission, stopped: true)
            }
        } catch {
            manifest.diagnostics.record(EngineeringFailure.capture(error, stage: .recorder, code: .recorderInvalid))
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
        }
        return try finish(configuration: configuration, recorder: recorder, manifest: &manifest)
    }

    private func capture(
        configuration: RunConfiguration, driver: AppleEngineDriver, recorder: RecorderOwner,
        admission: VPAAdmission?, manifest: inout AudioRunManifest
    ) throws {
        installTaps(driver: driver, recorder: recorder)
        let observer = ConfigurationChangeObserver(observedObject: driver.engine, recorder: recorder)
        let startTick = vp_recorder_now_tick()
        if let admission {
            try captureVPA(
                environment: (driver, recorder), observer: observer, startTick: startTick, admission: admission,
                manifest: &manifest)
            return
        }
        try PlaybackLifecycle.run(
            observer: observer,
            startAndValidate: {
                guard vp_recorder_arm(recorder.handle, startTick) else {
                    try observer.check()
                    throw EngineeringFailure(stage: .recorder, code: .recorderArmFailed)
                }
                try startAndWait(driver: driver)
                try observeRunning(driver: driver, manifest: &manifest)
            },
            play: { driver.player.play() },
            score: { wait(configuration: configuration, recorder: recorder, startTick: startTick) },
            stop: { stop(driver: driver) }
        )
    }

    private func captureVPA(
        environment: (driver: AppleEngineDriver, recorder: RecorderOwner), observer: ConfigurationChangeObserver,
        startTick: UInt64, admission: VPAAdmission, manifest: inout AudioRunManifest
    ) throws {
        let (driver, recorder) = environment
        manifest.vpaExperiment?.armTick = startTick
        var stopTick: UInt64?
        defer { manifest.vpaExperiment?.stopRequestTick = stopTick }
        try VPAWindow.capture(
            observer: observer,
            beforePlayback: {
                guard vp_recorder_arm(recorder.handle, startTick) else {
                    throw EngineeringFailure(stage: .recorder, code: .recorderArmFailed)
                }
                try startAndWait(driver: driver)
                try observeRunning(driver: driver, manifest: &manifest, admission: admission)
                manifest.vpaExperiment?.quietStartTick = vp_recorder_now_tick()
                try waitVPA(
                    seconds: VPARequest.quietSeconds, environment: environment, timing: (observer, startTick),
                    admission: admission, manifest: &manifest)
            },
            play: {
                let snapshot = vp_recorder_snapshot(recorder.handle)
                guard snapshot.invalid_reasons == 0, snapshot.input_written_frames > 0 else {
                    throw EngineeringFailure(stage: .recorder, code: .recorderInvalid)
                }
                manifest.vpaExperiment?.playRequestTick = vp_recorder_now_tick()
                driver.player.play()
                let playing = driver.player.isPlaying
                manifest.vpaExperiment?.playerPlayingAfterRequest = playing
                try VPAAdmission.requirePlaybackStarted(playing)
            },
            score: {
                try waitVPA(
                    seconds: VPARequest.materialSeconds, environment: environment, timing: (observer, startTick),
                    admission: admission, manifest: &manifest)
                manifest.vpaExperiment?.plannedTailStartTick = vp_recorder_now_tick()
                try waitVPA(
                    seconds: VPARequest.tailSeconds, environment: environment, timing: (observer, startTick),
                    admission: admission, manifest: &manifest)
                manifest.vpaExperiment?.windowsCompleted = true
            },
            cleanup: (
                invalidate: { vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT)) },
                stop: {
                    stopTick = vp_recorder_now_tick()
                    self.stop(driver: driver)
                }
            )
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

    private func stop(driver: AppleEngineDriver) {
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

    private func observeRunning(
        driver: AppleEngineDriver, manifest: inout AudioRunManifest, admission: VPAAdmission? = nil
    ) throws {
        let route = try readRoute(driver: driver)
        manifest.runningRoute = route
        if let admission {
            try admission.validateRoute(route)
            guard route == manifest.routeBefore else {
                throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
            }
        } else {
            guard route.hasVerifiedBinding, route.defaultInput == manifest.routeBefore.defaultInput,
                route.defaultOutput == manifest.routeBefore.defaultOutput
            else { throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged) }
        }
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
        if let experiment = manifest.vpaExperiment, !experiment.windowsCompleted, manifest.diagnostics.primary == nil {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .recorder, code: .experimentWindowInvalid))
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

extension VP0AudioSession {
    private func waitVPA(
        seconds: Double, environment: (driver: AppleEngineDriver, recorder: RecorderOwner),
        timing: (observer: ConfigurationChangeObserver, startTick: UInt64),
        admission: VPAAdmission, manifest: inout AudioRunManifest
    ) throws {
        let (driver, recorder) = environment
        let (observer, startTick) = timing
        try VPAWindow.wait(
            seconds: seconds,
            elapsedSeconds: {
                let now = vp_recorder_now_tick()
                let ticks = vp_recorder_ticks_for_seconds(1)
                return now >= startTick && ticks > 0 ? Double(now - startTick) / Double(ticks) : .nan
            },
            check: {
                try observer.check()
                guard vp_recorder_snapshot(recorder.handle).invalid_reasons == 0 else {
                    throw EngineeringFailure(stage: .recorder, code: .recorderInvalid)
                }
            },
            observe: {
                let tick = vp_recorder_now_tick()
                defer {
                    manifest.vpaExperiment?.observationCount += 1
                    let maximum = max(
                        manifest.vpaExperiment?.maximumObservationTicks ?? 0, vp_recorder_now_tick() - tick)
                    manifest.vpaExperiment?.maximumObservationTicks = maximum
                }
                try observeRunning(driver: driver, manifest: &manifest, admission: admission)
                try validateVPA(driver: driver, manifest: &manifest, admission: admission, stopped: false)
            }, sleep: { Thread.sleep(forTimeInterval: $0) })
    }

    private func validateVPA(
        driver: AppleEngineDriver, manifest: inout AudioRunManifest, admission: VPAAdmission, stopped: Bool
    ) throws {
        let isRunning = driver.isRunning
        if stopped {
            manifest.vpaExperiment?.postStopEngineObserved = isRunning
        } else {
            manifest.vpaExperiment?.runningEngineObserved = isRunning
        }
        guard isRunning != stopped else {
            throw EngineeringFailure(
                stage: stopped ? .engineStop : .engineStart, code: .experimentEngineStateMismatch)
        }
        if stopped, let route = manifest.postStopRoute { try admission.validateRoute(route) }
        if stopped {
            try VPAAdmission.validateStopped(manifest)
        }
        let playerVolume = driver.player.volume
        let mixerVolume = driver.engine.mainMixerNode.outputVolume
        if let evidence = manifest.vpaExperiment, let previous = evidence.playerVolume {
            guard previous == playerVolume, evidence.mixerVolume == mixerVolume else {
                throw EngineeringFailure(stage: .vpState, code: .vpStateChanged)
            }
        }
        manifest.vpaExperiment?.playerVolume = playerVolume
        manifest.vpaExperiment?.mixerVolume = mixerVolume
    }

}
