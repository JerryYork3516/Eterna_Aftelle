import AVFoundation
import CoreAudio
import Foundation
import VPRecorder
import VPReferenceCore

@MainActor
final class VPCSession {
    private var used = false

    func run(request: VPCRequest, preflight: VPBDisplayReceipt, prompt: VPCPrompt) throws -> AudioRunOutcome {
        try request.validate()
        try preflight.validate(id: "PREFLIGHT", requiresUser: true)
        try prompt.requireVisible()
        guard !used else { throw EngineeringFailure(stage: .recorder, code: .sessionAlreadyUsed) }
        used = true
        try MicrophonePermissionPlan.requireAuthorized(status: MicrophonePermissionAccess.currentStatus())
        guard let url = request.configuration.materialURL else {
            throw EngineeringFailure(stage: .sourceMaterial, code: .materialIdentityMismatch)
        }
        let material = try PCMSourceMaterial.load(url: url)
        let admission = try VPAAdmission.prepare(request: request.materialRequest, material: material)
        let driver = AppleEngineDriver(material: material.buffer)
        let beforeState = try EngineeringFailure.check(stage: .vpState, code: .stateReadFailed) {
            try driver.readVoiceProcessingState()
        }
        let beforeFormats = try EngineeringFailure.check(stage: .vpConfiguration, code: .formatReadFailed) {
            try driver.readFormats()
        }
        let configured = try ConfigurationPlan.configure(mode: request.configuration.mode, driver: driver)
        let route = try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.read(engine: driver.engine)
        }
        try admission.validateRoute(route)
        var manifest = try AudioRunManifest.create(
            configuration: request.configuration, configured: configured, route: route, driver: driver,
            material: material)
        manifest.vpcExperiment = VPCEvidence(
            preflight: preflight, registrationSHA256: admission.registrationSHA256,
            materialSafety: admission.materialSafety, preConfigurationState: beforeState,
            preConfigurationFormats: beforeFormats)
        manifest.diagnosticClockOrigin =
            "VP-C fixed-origin 13+.5 deadlines, .5 control reserve; local brackets; no acoustic mapping"
        manifest.snapshotTiming =
            "VP-C configured/running/control/stopped; play request, player state and Render separate"
        let recorder = try RecorderOwner(
            configuration: request.configuration, maximumSeconds: VPARequest.maximumSeconds)
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
        driver: AppleEngineDriver, recorder: RecorderOwner, manifest: inout AudioRunManifest, prompt: VPCPrompt
    ) throws {
        NativePCMTap.install(node: driver.engine.inputNode, stream: UInt32(VP_STREAM_INPUT), recorder: recorder)
        NativePCMTap.install(node: driver.engine.mainMixerNode, stream: UInt32(VP_STREAM_RENDER), recorder: recorder)
        let observer = ConfigurationChangeObserver(observedObject: driver.engine, recorder: recorder)
        let arm = vp_recorder_now_tick()
        manifest.vpcExperiment?.armTick = arm
        try VPBWindow.capture(
            admission: (manifest.vpcExperiment?.preflight.userConfirmed == true, observer),
            start: {
                try prompt.requireVisible()
                guard vp_recorder_arm(recorder.handle, arm) else {
                    throw EngineeringFailure(stage: .recorder, code: .recorderArmFailed)
                }
                try manifest.vpcExperiment?.append(VPBClockRead.read("beforeStart"))
                try VPCWindow.start(
                    schedule: { driver.schedulePlayback() },
                    prepare: {
                        try EngineeringFailure.check(stage: .enginePrepare, code: .enginePrepareFailed) {
                            driver.engine.prepare()
                        }
                    },
                    start: {
                        try prompt.requireVisible()
                        try EngineeringFailure.check(stage: .engineStart, code: .engineStartFailed) {
                            try driver.engine.start()
                        }
                    }, validate: { try observe(driver: driver, manifest: &manifest, stopped: false) })
            },
            window: {
                try wait(
                    driver: driver, diagnostic: (recorder, observer), arm: arm, manifest: &manifest,
                    prompt: prompt)
            }, invalidate: { vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT)) },
            stop: {
                manifest.vpcExperiment?.stopRequested = VPBClockRead.read("stopRequest")
                manifest.vpcExperiment?.playerPlayingBeforeStop = driver.player.isPlaying
                driver.player.stop()
                driver.engine.stop()
                manifest.vpcExperiment?.stoppedEngineObserved = driver.engine.isRunning
                manifest.vpcExperiment?.playerPlayingAfterStop = driver.player.isPlaying
                driver.engine.inputNode.removeTap(onBus: 0)
                driver.engine.mainMixerNode.removeTap(onBus: 0)
            })
    }

    private func wait(
        driver: AppleEngineDriver, diagnostic: (recorder: RecorderOwner, observer: ConfigurationChangeObserver),
        arm: UInt64, manifest: inout AudioRunManifest, prompt: VPCPrompt
    ) throws {
        let recorder = diagnostic.recorder
        let observer = diagnostic.observer
        let clock = VPBClockRead.read("budget")
        try VPCWindow.run(
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
                return (
                    state.input_written_records > 0 && state.input_written_frames > 0,
                    state.render_written_records > 0 && state.render_written_frames > 0
                )
            },
            event: { id in
                let value = VPBClockRead.read(id)
                try manifest.vpcExperiment?.append(value)
                return value
            },
            perform: { action in
                switch action {
                case .play:
                    driver.player.play()
                    manifest.vpcExperiment?.playerPlayingAfterRequest = driver.player.isPlaying
                    try VPAAdmission.requirePlaybackStarted(driver.player.isPlaying)
                    return nil
                case .cue(let phase):
                    let receipt = try prompt.cue(phase)
                    guard (manifest.vpcExperiment?.receipts.count ?? 6) < 6 else {
                        throw EngineeringFailure(stage: .command, code: .promptUnconfirmed)
                    }
                    manifest.vpcExperiment?.receipts.append(receipt)
                    return receipt
                }
            }, wait: { prompt.wait($0) })
    }

    private func observe(driver: AppleEngineDriver, manifest: inout AudioRunManifest, stopped: Bool) throws {
        if stopped {
            manifest.vpcExperiment?.stoppedEngineObserved = driver.isRunning
        } else {
            manifest.vpcExperiment?.runningEngineObserved = driver.isRunning
        }
        try SourceProbeRoutePolicy.validateEngineState(isRunning: driver.isRunning, stopped: stopped)
        let route = try EngineeringFailure.check(stage: .deviceBinding, code: .deviceReadFailed) {
            try AudioRouteSnapshot.read(engine: driver.engine)
        }
        if stopped { manifest.postStopRoute = route } else { manifest.runningRoute = route }
        try VPBSession.validateRoute(
            route, mode: manifest.mode, input: manifest.routeBefore.defaultInput,
            output: manifest.routeBefore.defaultOutput)
        guard route == manifest.routeBefore else {
            throw EngineeringFailure(stage: .deviceBinding, code: .routeChanged)
        }
        let state = try EngineeringFailure.check(stage: .vpState, code: .stateReadFailed) {
            try driver.readVoiceProcessingState()
        }
        if stopped { manifest.postStopState = state } else { manifest.runningState = state }
        let formats = try EngineeringFailure.check(stage: .vpConfiguration, code: .formatReadFailed) {
            try driver.readFormats()
        }
        let hardware = AppleEngineDriver.snapshot(driver.engine.outputNode.outputFormat(forBus: 0))

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
        try RunningConfigurationPlan.validate(
            configured: manifest.configured, expectedHardwareOutput: manifest.hardwareOutputFormat,
            actual: RunningConfigurationSnapshot(state: state, formats: formats, hardwareOutput: hardware))
    }

    nonisolated static func finish(
        recorder: RecorderOwner, manifest: inout AudioRunManifest, directory: URL
    ) throws -> AudioRunOutcome {
        if !recorder.seal() { manifest.diagnostics.record(EngineeringDiagnostic(stage: .seal, code: .sealFailed)) }
        let outcome = recorder.outcome(directory: directory, expectsRender: true)
        manifest.outcome = outcome
        let badCounters = [
            outcome.lostRecords, outcome.overflowRecords, outcome.pendingRecords,
            outcome.discardedRecords, outcome.suppressedRecords, outcome.missingSampleTimeRecords,
            outcome.missingHostTimeRecords
        ].contains { $0 != 0 }
        if !outcome.isCompleteForReference || badCounters {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .recorder, code: .recorderInvalid))
        }
        if outcome.isCompleteForReference && !badCounters {
            do {
                let analysis = try VPCPCMRead.evaluate(
                    directory: directory, events: manifest.vpcExperiment?.events ?? [],
                    receipts: manifest.vpcExperiment?.receipts ?? [],
                    arm: manifest.vpcExperiment?.armTick)
                manifest.vpcExperiment?.analysis = analysis
                if analysis.status != "DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT" {
                    manifest.diagnostics.record(
                        EngineeringDiagnostic(stage: .recorder, code: .experimentCoverageUnverified))
                }
                if (analysis.inputChannels + analysis.renderChannels).contains(where: { $0.nonFinite > 0 }) {
                    manifest.diagnostics.record(
                        EngineeringDiagnostic(stage: .inputFormat, code: .inputNonFiniteSamples))
                }
            } catch {
                manifest.diagnostics.record(
                    EngineeringFailure.capture(error, stage: .recorder, code: .experimentCoverageUnverified))
            }
        }
        manifest.vpcExperiment?.engineeringValidity =
            manifest.diagnostics.primary == nil ? "ENGINEERING_VALID" : "INVALID"
        manifest.terminalStatus = manifest.diagnostics.primary == nil ? "VPC_SEALED_ACOUSTICS_UNVERIFIED" : "INVALID"
        do { try manifest.writeFinal(directory: directory) } catch {
            manifest.diagnostics.record(EngineeringDiagnostic(stage: .evidenceWrite, code: .finalWriteFailed))
            manifest.vpcExperiment?.engineeringValidity = "INVALID"
            manifest.terminalStatus = "INVALID"
        }
        if manifest.diagnostics.primary != nil { throw EngineeringFailure(diagnostics: manifest.diagnostics) }
        return outcome
    }
}
