import AVFoundation
import CoreAudio
import Foundation
import VPRecorder
import VPReferenceCore

@MainActor
final class VPBSession {
    private var used = false

    func run(request: VPBRequest, preflight: VPBDisplayReceipt, prompt: VPBPrompt) throws -> AudioRunOutcome {
        try request.validate()
        try preflight.validate(id: "PREFLIGHT", requiresUser: true)
        try prompt.requireVisible()
        guard !used else { throw EngineeringFailure(stage: .recorder, code: .sessionAlreadyUsed) }
        used = true
        try MicrophonePermissionPlan.requireAuthorized(status: MicrophonePermissionAccess.currentStatus())
        let registered = try EngineeringFailure.check(stage: .command, code: .invalidArguments) {
            try SourceProbeRegistrationFile.load(request.registrationURL)
        }
        let defaults = try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.readDefaultsForVPB(registration: registered.registration)
        }
        let driver = AppleEngineDriver(material: nil)
        let configured = try ConfigurationPlan.configure(mode: request.configuration.mode, driver: driver)
        let route = try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.read(engine: driver.engine)
        }
        try Self.validateRoute(route, mode: request.configuration.mode, input: defaults.0, output: defaults.1)
        var manifest = try AudioRunManifest.create(
            configuration: request.configuration, configured: configured, route: route, driver: driver, material: nil)
        manifest.vpbExperiment = VPBEvidence(preflight: preflight)
        manifest.diagnosticClockOrigin =
            "VP-B arm-relative continuous budget; event-local absolute brackets; no acoustic mapping"
        manifest.snapshotTiming = "VP-B no playback; configured/running/boundary/stopped snapshots"
        let recorder = try RecorderOwner(
            configuration: request.configuration, maximumSeconds: VPBRequest.maximumSeconds)
        do {
            try manifest.writePrepared(directory: request.configuration.outputDirectory)
            try capture(driver: driver, recorder: recorder, manifest: &manifest, prompt: prompt)
            try observe(driver: driver, manifest: &manifest, stopped: true)
        } catch {
            manifest.diagnostics.record(EngineeringFailure.capture(error, stage: .recorder, code: .recorderInvalid))
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
        }
        return try Self.finish(
            recorder: recorder, manifest: &manifest, directory: request.configuration.outputDirectory)
    }

    private func capture(
        driver: AppleEngineDriver, recorder: RecorderOwner, manifest: inout AudioRunManifest, prompt: VPBPrompt
    ) throws {
        NativePCMTap.install(node: driver.engine.inputNode, stream: UInt32(VP_STREAM_INPUT), recorder: recorder)
        NativePCMTap.install(node: driver.engine.mainMixerNode, stream: UInt32(VP_STREAM_RENDER), recorder: recorder)
        let observer = ConfigurationChangeObserver(observedObject: driver.engine, recorder: recorder)
        let arm = vp_recorder_now_tick()
        manifest.vpbExperiment?.armTick = arm
        try VPBWindow.capture(
            admission: (manifest.vpbExperiment?.preflight.userConfirmed == true, observer),
            start: {
                try prompt.requireVisible()
                guard vp_recorder_arm(recorder.handle, arm) else {
                    throw EngineeringFailure(stage: .recorder, code: .recorderArmFailed)
                }
                try manifest.vpbExperiment?.append(VPBClockRead.read("beforeStart"))
                try EngineeringFailure.check(stage: .enginePrepare, code: .enginePrepareFailed) {
                    driver.engine.prepare()
                }
                try prompt.requireVisible()
                try EngineeringFailure.check(stage: .engineStart, code: .engineStartFailed) {
                    try driver.engine.start()
                }
                try observe(driver: driver, manifest: &manifest, stopped: false)
            },
            window: {
                try wait(
                    driver: driver, diagnostic: (recorder, observer), arm: arm, manifest: &manifest,
                    prompt: prompt)
            }, invalidate: { vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT)) },
            stop: {
                driver.engine.stop()
                driver.engine.inputNode.removeTap(onBus: 0)
                driver.engine.mainMixerNode.removeTap(onBus: 0)
            })
    }

    private func wait(
        driver: AppleEngineDriver, diagnostic: (recorder: RecorderOwner, observer: ConfigurationChangeObserver),
        arm: UInt64, manifest: inout AudioRunManifest, prompt: VPBPrompt
    ) throws {
        let recorder = diagnostic.recorder
        let observer = diagnostic.observer
        let clock = VPBClockRead.read("budget")
        try VPBWindow.run(
            clock: (
                arm,
                {
                    let now = vp_recorder_now_tick()
                    return now >= arm && clock.valid ? clock.seconds(now - arm) : .nan
                }
            ),
            observe: { full in
                let before = vp_recorder_now_tick()
                try observer.check()
                try prompt.requireVisible()
                let state = vp_recorder_snapshot(recorder.handle)
                guard state.invalid_reasons == 0, !state.writer_failure, state.lost_records == 0,
                    state.overflow_records == 0, state.missing_host_time_records == 0,
                    state.missing_sample_time_records == 0
                else { throw EngineeringFailure(stage: .recorder, code: .recorderInvalid) }
                if full { try observe(driver: driver, manifest: &manifest, stopped: false) }
                guard clock.seconds(vp_recorder_now_tick() - before) <= 0.25 else {
                    throw EngineeringFailure(stage: .recorder, code: .experimentWindowInvalid)
                }
                return state.input_written_records > 0 && state.input_written_frames > 0
            },
            event: { id in
                let value = VPBClockRead.read(id)
                try manifest.vpbExperiment?.append(value)
                return value
            },
            cue: { phase in
                let receipt = try prompt.cue(phase)
                try receipt.validate(id: phase.rawValue)
                guard (manifest.vpbExperiment?.receipts.count ?? 8) < 8 else {
                    throw EngineeringFailure(stage: .command, code: .promptUnconfirmed)
                }
                manifest.vpbExperiment?.receipts.append(receipt)
            }, wait: { prompt.wait($0) })
    }

    private func observe(driver: AppleEngineDriver, manifest: inout AudioRunManifest, stopped: Bool) throws {
        try SourceProbeRoutePolicy.validateEngineState(isRunning: driver.isRunning, stopped: stopped)
        let route = try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.read(engine: driver.engine)
        }
        try Self.validateRoute(
            route, mode: manifest.mode, input: manifest.routeBefore.defaultInput,
            output: manifest.routeBefore.defaultOutput)
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
        try RunningConfigurationPlan.validate(
            configured: manifest.configured, expectedHardwareOutput: manifest.hardwareOutputFormat,
            actual: RunningConfigurationSnapshot(state: state, formats: formats, hardwareOutput: hardware))
        if stopped {
            manifest.postStopRoute = route
            manifest.postStopState = state
            manifest.postStopFormats = formats
            manifest.postStopHardwareOutputFormat = hardware
        } else {
            manifest.runningRoute = route
            manifest.runningState = state
            manifest.runningFormats = formats
            manifest.runningHardwareOutputFormat = hardware
        }
    }

    nonisolated static func validateRoute(
        _ route: AudioRouteSnapshot, mode: VPMode, input: AudioDeviceSnapshot, output: AudioDeviceSnapshot
    ) throws {
        guard route.defaultInput == input, route.defaultOutput == output else {
            throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
        }
        if mode == .enabled {
            try SourceProbeRoutePolicy.validate(route)
        } else if !route.hasVerifiedBinding {
            throw EngineeringFailure(stage: .deviceBinding, code: .deviceBindingMismatch)
        }
    }

    nonisolated static func finish(
        recorder: RecorderOwner, manifest: inout AudioRunManifest, directory: URL
    ) throws -> AudioRunOutcome {
        if !recorder.seal() { manifest.diagnostics.record(EngineeringDiagnostic(stage: .seal, code: .sealFailed)) }
        let outcome = recorder.outcome(directory: directory, expectsRender: false)
        manifest.outcome = outcome
        if !outcome.isCompleteForReference {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .recorder, code: .recorderInvalid))
        }
        if outcome.isCompleteForReference {
            do {
                let analysis = try VPBPCMRead.evaluate(
                    directory: directory, events: manifest.vpbExperiment?.events ?? [],
                    expectedArmTick: manifest.vpbExperiment?.armTick)
                manifest.vpbExperiment?.analysis = analysis
                if analysis.status != "DIGITAL_INPUT_SPAN_COVERED" {
                    manifest.diagnostics.record(
                        EngineeringDiagnostic(stage: .recorder, code: .experimentCoverageUnverified))
                }
                if analysis.inputChannels.contains(where: { $0.nonFinite > 0 }) {
                    manifest.diagnostics.record(
                        EngineeringDiagnostic(stage: .inputFormat, code: .inputNonFiniteSamples))
                }
            } catch {
                manifest.diagnostics.record(
                    EngineeringFailure.capture(error, stage: .recorder, code: .experimentCoverageUnverified))
            }
        }
        manifest.terminalStatus = manifest.diagnostics.primary == nil ? "VPB_SEALED_CONTENT_UNVERIFIED" : "INVALID"
        do { try manifest.writeFinal(directory: directory) } catch {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .evidenceWrite, code: .finalWriteFailed))
        }
        if manifest.diagnostics.primary != nil { throw EngineeringFailure(diagnostics: manifest.diagnostics) }
        return outcome
    }
}

extension AudioRouteSnapshot {
    static func readDefaultsForVPB(registration: SourceProbeRegistration) throws -> (
        AudioDeviceSnapshot, AudioDeviceSnapshot
    ) {
        let input = try AudioDeviceSnapshot.read(
            identifier: AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice))
        let output = try AudioDeviceSnapshot.read(
            identifier: AudioDeviceSnapshot.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice))
        try registration.validateDefaults(
            inputID: input.anonymousID, outputID: output.anonymousID,
            isUSB: input.transport == kAudioDeviceTransportTypeUSB,
            isBuiltIn: output.transport == kAudioDeviceTransportTypeBuiltIn)
        return (input, output)
    }
}
