import AVFoundation
import CoreAudio
import Darwin
import Foundation
import VPRecorder
import VPReferenceCore

final class SourceProbe {
    private var used = false

    func run(request: SourceProbeRequest) throws -> AudioRunOutcome {
        try request.validate()
        guard !used else { throw EngineeringFailure(stage: .recorder, code: .sessionAlreadyUsed) }
        used = true
        try MicrophonePermissionPlan.requireAuthorized(status: MicrophonePermissionAccess.currentStatus())
        let registration = try EngineeringFailure.check(stage: .command, code: .invalidArguments) {
            try SourceProbeRegistrationFile.load(request.registrationURL)
        }
        let defaults = try readDefaults(registration: registration.registration)
        let driver = AppleEngineDriver(material: nil)
        let configured = try ConfigurationPlan.configure(mode: .enabled, driver: driver)
        let route = try readRoute(driver: driver)
        try SourceProbeRoutePolicy.validate(route)
        guard route.defaultInput == defaults.input, route.defaultOutput == defaults.output else {
            throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
        }
        let configuration = request.configuration
        var manifest = try EngineeringFailure.check(stage: .evidenceWrite, code: .identityFailed) {
            try AudioRunManifest.create(
                configuration: configuration, configured: configured, route: route, driver: driver, material: nil)
        }
        manifest.sourceProbe = SourceProbeEvidence(
            registrationSHA256: registration.sha256,
            defaultInputBeforeVP: defaults.input, defaultOutputBeforeVP: defaults.output)
        manifest.diagnosticClockOrigin =
            "MACH_CONTINUOUS_TIME; source-probe 8s admission from arm before prepare/start; "
            + "raw AVAudioTime.hostTime retains its separate clock domain"
        manifest.snapshotTiming =
            "SOURCE_PROBE: latest post-start/control-poll snapshot; terminal snapshots follow stop; no playback"
        let recorder = try EngineeringFailure.check(stage: .recorder, code: .recorderCreateFailed) {
            try RecorderOwner(configuration: configuration, maximumSeconds: SourceProbeRequest.maximumSeconds)
        }
        do {
            try EngineeringFailure.check(stage: .evidenceWrite, code: .preparedWriteFailed) {
                try manifest.writePrepared(directory: configuration.outputDirectory)
            }
            try capture(driver: driver, recorder: recorder, manifest: &manifest)
            try observe(driver: driver, manifest: &manifest, stopped: true)
        } catch {
            manifest.diagnostics.record(EngineeringFailure.capture(error, stage: .recorder, code: .recorderInvalid))
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
        }
        return try finish(recorder: recorder, manifest: &manifest, directory: configuration.outputDirectory)
    }

    private func readDefaults(registration: SourceProbeRegistration) throws -> (
        input: AudioDeviceSnapshot, output: AudioDeviceSnapshot
    ) {
        try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            let inputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
            let outputID = try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
            let input = try AudioDeviceSnapshot.read(identifier: inputID)
            let output = try AudioDeviceSnapshot.read(identifier: outputID)
            try registration.validateDefaults(
                inputID: input.anonymousID, outputID: output.anonymousID,
                isUSB: input.transport == kAudioDeviceTransportTypeUSB,
                isBuiltIn: output.transport == kAudioDeviceTransportTypeBuiltIn)
            guard try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice) == inputID,
                try AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice) == outputID
            else { throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged) }
            return (input, output)
        }
    }

    private func capture(driver: AppleEngineDriver, recorder: RecorderOwner, manifest: inout AudioRunManifest) throws {
        NativePCMTap.install(node: driver.engine.inputNode, stream: UInt32(VP_STREAM_INPUT), recorder: recorder)
        NativePCMTap.install(node: driver.engine.mainMixerNode, stream: UInt32(VP_STREAM_RENDER), recorder: recorder)
        let observer = ConfigurationChangeObserver(observedObject: driver.engine, recorder: recorder)
        let startTick = vp_recorder_now_tick()
        try SourceProbeWindow.capture(
            observer: observer,
            startAndValidate: {
                try invalidateOnFailure(recorder: recorder) {
                    guard vp_recorder_arm(recorder.handle, startTick) else {
                        try observer.check()
                        throw EngineeringFailure(stage: .recorder, code: .recorderArmFailed)
                    }
                    try EngineeringFailure.check(stage: .enginePrepare, code: .enginePrepareFailed) {
                        driver.engine.prepare()
                    }
                    try EngineeringFailure.check(stage: .engineStart, code: .engineStartFailed) {
                        try driver.engine.start()
                    }
                    try observe(driver: driver, manifest: &manifest, stopped: false)
                }
            },
            window: {
                try invalidateOnFailure(recorder: recorder) {
                    try window(
                        driver: driver, recorder: recorder, observer: observer, startTick: startTick,
                        manifest: &manifest)
                }
            },
            stop: {
                driver.engine.stop()
                driver.engine.inputNode.removeTap(onBus: 0)
                driver.engine.mainMixerNode.removeTap(onBus: 0)
            })
    }

    func invalidateOnFailure(recorder: RecorderOwner, operation: () throws -> Void) throws {
        do { try operation() } catch {
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
            throw error
        }
    }

    private func window(
        driver: AppleEngineDriver, recorder: RecorderOwner, observer: ConfigurationChangeObserver,
        startTick: UInt64, manifest: inout AudioRunManifest
    ) throws {
        try SourceProbeWindow.run(
            durationSeconds: manifest.durationSeconds,
            elapsedSeconds: {
                let now = vp_recorder_now_tick()
                let ticks = vp_recorder_ticks_for_seconds(1)
                guard now >= startTick, ticks > 0 else { return .nan }
                return Double(now - startTick) / Double(ticks)
            },
            observe: {
                try observer.check()
                guard vp_recorder_snapshot(recorder.handle).invalid_reasons == 0 else {
                    throw EngineeringFailure(stage: .recorder, code: .recorderInvalid)
                }
                try observe(driver: driver, manifest: &manifest, stopped: false)
            },
            cue: { phase, elapsed in
                manifest.sourceProbe?.cues.append(.init(phase: phase, armRelativeSeconds: elapsed))
                print("source_probe_cue=\(phase.rawValue) arm_relative_seconds=\(elapsed)")
                fflush(stdout)
            }, wait: { Thread.sleep(forTimeInterval: $0) })
    }

    private func readRoute(driver: AppleEngineDriver) throws -> AudioRouteSnapshot {
        try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.read(engine: driver.engine)
        }
    }

    private func observe(driver: AppleEngineDriver, manifest: inout AudioRunManifest, stopped: Bool) throws {
        let isRunning = driver.isRunning
        if stopped {
            manifest.sourceProbe?.postStopEngineObserved = isRunning
        } else {
            manifest.sourceProbe?.runningEngineObserved = isRunning
        }
        try SourceProbeRoutePolicy.validateEngineState(isRunning: isRunning, stopped: stopped)
        let route = try readRoute(driver: driver)
        if stopped { manifest.postStopRoute = route } else { manifest.runningRoute = route }
        try SourceProbeRoutePolicy.validate(route)
        guard route == manifest.routeBefore else {
            throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
        }
        let state = try EngineeringFailure.check(stage: .vpState, code: .stateReadFailed) {
            try driver.readVoiceProcessingState()
        }
        let formats = try EngineeringFailure.check(stage: .vpConfiguration, code: .formatReadFailed) {
            try driver.readFormats()
        }
        let hardware = AppleEngineDriver.snapshot(driver.engine.outputNode.outputFormat(forBus: 0))
        if stopped {
            manifest.postStopState = state
            manifest.postStopFormats = formats
            manifest.postStopHardwareOutputFormat = hardware
        } else {
            manifest.runningState = state
            manifest.runningFormats = formats
            manifest.runningHardwareOutputFormat = hardware
        }
        try RunningConfigurationPlan.validate(
            configured: manifest.configured, expectedHardwareOutput: manifest.hardwareOutputFormat,
            actual: RunningConfigurationSnapshot(state: state, formats: formats, hardwareOutput: hardware))
    }

    func finish(recorder: RecorderOwner, manifest: inout AudioRunManifest, directory: URL) throws -> AudioRunOutcome {
        if !recorder.seal() { manifest.diagnostics.record(EngineeringDiagnostic(stage: .seal, code: .sealFailed)) }
        let outcome = recorder.outcome(directory: directory, expectsRender: false)
        if !outcome.isCompleteForReference, manifest.diagnostics.primary == nil {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .recorder, code: .recorderInvalid))
        }
        manifest.outcome = outcome
        manifest.sourceProbe?.inputObservation = outcome.inputWrittenFrames > 0 ? "INPUT_PCM_PRESENT" : "NOT_MEASURED"
        manifest.terminalStatus = manifest.diagnostics.primary == nil ? "PROBE_SEALED_SOURCE_UNVERIFIED" : "INVALID"
        do { try manifest.writeFinal(directory: directory) } catch {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .evidenceWrite, code: .finalWriteFailed))
        }
        if manifest.diagnostics.primary != nil { throw EngineeringFailure(diagnostics: manifest.diagnostics) }
        return outcome
    }
}
