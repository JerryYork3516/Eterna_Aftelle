import AVFoundation
import Foundation
import VPRecorder
import VPReferenceCore

public final class VP0AudioSession {
    private var used = false

    public init() {}

    public func run(configuration: RunConfiguration) throws -> AudioRunOutcome {
        try configuration.validateForAudio()
        guard !used else { throw AudioReferenceError.sessionAlreadyUsed }
        used = true
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioReferenceError.permissionRequired
        }
        let material = try configuration.materialURL.map(PCMSourceMaterial.load)
        let driver = AppleEngineDriver(material: material?.buffer)
        let configured = try ConfigurationPlan.configure(mode: configuration.mode, driver: driver)
        let route = try AudioRouteSnapshot.read(engine: driver.engine)
        var manifest = try AudioRunManifest.create(
            configuration: configuration, configured: configured, route: route, driver: driver, material: material
        )
        let recorder = try RecorderOwner(configuration: configuration)
        defer { recorder.seal() }
        try manifest.writePrepared(directory: configuration.outputDirectory)
        guard route.deviceBindingStatus == "NODE_IDS_MATCH_DEFAULTS" else {
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
            recorder.seal()
            manifest.terminalStatus = "BLOCKED_DEVICE_BINDING_UNAVAILABLE"
            manifest.outcome = recorder.outcome(
                directory: configuration.outputDirectory, expectsRender: configuration.materialURL != nil
            )
            try manifest.writeFinal(directory: configuration.outputDirectory)
            throw AudioReferenceError.unavailableDevice
        }
        return try capture(configuration: configuration, driver: driver, recorder: recorder, manifest: &manifest)
    }

    private func capture(
        configuration: RunConfiguration, driver: AppleEngineDriver, recorder: RecorderOwner,
        manifest: inout AudioRunManifest
    ) throws -> AudioRunOutcome {
        installTaps(driver: driver, recorder: recorder)
        var observer: NSObjectProtocol?
        do {
            try startAndWait(
                configuration: configuration, driver: driver, recorder: recorder,
                manifest: &manifest, observer: &observer
            )
        } catch {
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_ABORT))
            stop(driver: driver, observer: observer)
            recorder.seal()
            manifest.terminalStatus = "FAILED"
            manifest.outcome = recorder.outcome(
                directory: configuration.outputDirectory, expectsRender: configuration.materialURL != nil
            )
            do {
                try manifest.writeFinal(directory: configuration.outputDirectory)
            } catch {
                throw AudioReferenceError.evidenceWriteFailed
            }
            throw error
        }
        stop(driver: driver, observer: observer)
        observeAfterStop(driver: driver, recorder: recorder, manifest: &manifest)
        recorder.seal()
        let outcome = recorder.outcome(
            directory: configuration.outputDirectory, expectsRender: configuration.materialURL != nil
        )
        manifest.outcome = outcome
        manifest.terminalStatus = outcome.status
        try manifest.writeFinal(directory: configuration.outputDirectory)
        return outcome
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

    private func startAndWait(
        configuration: RunConfiguration, driver: AppleEngineDriver,
        recorder: RecorderOwner, manifest: inout AudioRunManifest, observer: inout NSObjectProtocol?
    ) throws {
        let startTick = vp_recorder_now_tick()
        guard vp_recorder_arm(recorder.handle, startTick) else {
            throw AudioReferenceError.recorderUnavailable
        }
        driver.schedulePlayback()
        driver.engine.prepare()
        try driver.engine.start()
        do {
            try observeRunning(driver: driver, recorder: recorder, manifest: &manifest)
        } catch {
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_FORMAT))
            manifest.terminalStatus = "INVALID_RUNNING_SNAPSHOT"
        }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: driver.engine, queue: nil
        ) { _ in vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_FORMAT)) }
        driver.player.play()
        DiagnosticLifecycle.finishWindow(
            durationSeconds: configuration.durationSeconds,
            elapsedSeconds: {
                Double(vp_recorder_now_tick() - startTick) / Double(vp_recorder_ticks_for_seconds(1))
            },
            observe: {},
            onFailure: { _ in
                vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_WRITE))
                manifest.terminalStatus = "INVALID_DIAGNOSTIC_OBSERVATION"
            },
            wait: { Thread.sleep(forTimeInterval: $0) }
        )
    }

    private func observeAfterStop(
        driver: AppleEngineDriver, recorder: RecorderOwner, manifest: inout AudioRunManifest
    ) {
        do {
            manifest.postStopRoute = try AudioRouteSnapshot.read(engine: driver.engine)
            manifest.postStopFormats = try driver.readFormats()
            manifest.postStopState = try driver.readVoiceProcessingState()
            manifest.postStopHardwareOutputFormat = AppleEngineDriver.snapshot(
                driver.engine.outputNode.outputFormat(forBus: 0)
            )
            if manifest.postStopRoute != manifest.routeBefore {
                vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_FORMAT))
            }
        } catch {
            vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_FORMAT))
            manifest.terminalStatus = "INVALID_POST_STOP_SNAPSHOT"
        }
    }

    private func observeRunning(
        driver: AppleEngineDriver, recorder: RecorderOwner, manifest: inout AudioRunManifest
    ) throws {
        manifest.runningFormats = try driver.readFormats()
        manifest.runningState = try driver.readVoiceProcessingState()
        manifest.runningHardwareOutputFormat = AppleEngineDriver.snapshot(
            driver.engine.outputNode.outputFormat(forBus: 0)
        )
        let consistent =
            manifest.runningFormats == manifest.configured.formats
            && manifest.runningState == manifest.configured.state
            && manifest.runningHardwareOutputFormat == manifest.hardwareOutputFormat
        if !consistent { vp_recorder_invalidate(recorder.handle, UInt32(VP_INVALID_FORMAT)) }
        manifest.terminalStatus = consistent ? "RUNNING" : "INVALID_RUNNING_CONFIGURATION"
    }
}
