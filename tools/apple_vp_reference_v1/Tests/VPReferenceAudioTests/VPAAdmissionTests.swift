import AVFoundation
import CoreAudio
import CryptoKit
import Foundation
import VPRecorder
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPAAdmissionTests: XCTestCase {
    private func request(mode: VPMode = .enabled, authorized: Bool = true) -> VPARequest {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return VPARequest(
            configuration: RunConfiguration(
                mode: mode, durationSeconds: 16, diagnosticsArmed: true, audioExplicitlyEnabled: true,
                outputDirectory: root.appendingPathComponent("run"),
                materialURL: root.appendingPathComponent("sound.wav"),
                studyID: "synthetic-echo"), experimentAuthorized: authorized,
            targetRegistrationURL: root.appendingPathComponent("registration.json"),
            materialSHA256: String(repeating: "a", count: 64), nativePCMSHA256: String(repeating: "b", count: 64))
    }

    private func identity(
        fileSHA: String = String(repeating: "a", count: 64),
        pcmSHA: String = String(repeating: "b", count: 64), frames: UInt64 = 128_000,
        rate: Double = 16_000, start: Int64 = 0
    ) -> PCMSourceIdentity {
        PCMSourceIdentity(
            sha256: fileSHA, nativePCMSHA256: pcmSHA, fileBytes: 512_000, sourceStartFrame: start,
            sourceFrameCount: frames,
            nativeFormat: NativeAudioFormat(
                sampleRate: rate, channelCount: 3, formatID: kAudioFormatLinearPCM,
                formatFlags: 41, bytesPerFrame: 4, bitsPerChannel: 32))
    }

    func testMissingConsentFailsBeforePermissionOrEngineOrEvidenceCreation() {
        let value = request(authorized: false)
        XCTAssertThrowsError(try VP0AudioSession().runVPA(request: value))
        XCTAssertFalse(FileManager.default.fileExists(atPath: value.configuration.outputDirectory.path))
    }

    func testMatchingMaterialIdentityAndCompleteEightSecondRange() throws {
        try VPAAdmission.validateMaterial(request: request(), identity: identity())
    }

    func testChangedFileOrNativePCMIdentityIsRejected() {
        for changed in [identity(fileSHA: "changed"), identity(pcmSHA: "changed")] {
            XCTAssertThrowsError(try VPAAdmission.validateMaterial(request: request(), identity: changed)) { error in
                XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "MATERIAL_IDENTITY_MISMATCH")
            }
        }
    }

    func testMissingPartialShiftedOrInvalidDurationMaterialIsRejected() {
        let values: [PCMSourceIdentity?] = [
            nil, identity(frames: 127_999), identity(frames: 128_001), identity(rate: .nan), identity(start: 1)
        ]
        for value in values {
            XCTAssertThrowsError(try VPAAdmission.validateMaterial(request: request(), identity: value))
        }
    }

    func testOnUnknownDevicePresentationRemainsDiagnosticAndOffGuardStillRejects() throws {
        let route = SourceProbeFixture.route()
        let enabled = VPAAdmission(
            request: request(), registrationSHA256: "synthetic", input: SourceProbeFixture.input,
            output: SourceProbeFixture.output)
        try enabled.validateRoute(route)
        XCTAssertFalse(route.hasVerifiedBinding)
        let off = VPAAdmission(
            request: request(mode: .disabled), registrationSHA256: "synthetic", input: SourceProbeFixture.input,
            output: SourceProbeFixture.output)
        XCTAssertThrowsError(try off.validateRoute(route))
    }

    func testThirdNodeOrChangedRegisteredDefaultIsRejected() {
        let value = VPAAdmission(
            request: request(), registrationSHA256: "synthetic", input: SourceProbeFixture.input,
            output: SourceProbeFixture.output)
        let unknown = AudioDeviceSnapshot(
            anonymousID: String(repeating: "f", count: 64), transport: kAudioDeviceTransportTypeUSB,
            nominalSampleRate: 16_000)
        XCTAssertThrowsError(try value.validateRoute(SourceProbeFixture.route(nodeInput: unknown)))
        let changed = VPAAdmission(
            request: request(), registrationSHA256: "synthetic", input: unknown, output: SourceProbeFixture.output)
        XCTAssertThrowsError(try changed.validateRoute(SourceProbeFixture.route()))
    }

    func testSourceEvidenceCannotGrantQualificationOrConfirmChannelRoles() throws {
        let evidence = VPAEvidence(registrationSHA256: "synthetic")
        XCTAssertEqual(evidence.sourceStatus, "SOURCE_UNVERIFIED")
        XCTAssertFalse(evidence.sourceQualificationGranted)
        XCTAssertFalse(evidence.windowsCompleted)
        let data = try JSONEncoder().encode(evidence)
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("SOURCE_CONFIRMED"))
    }

    func testOrdinaryManifestOmitsExperimentSchema() throws {
        let fixture = try SourceProbeFixture()
        let data = try JSONEncoder().encode(fixture.manifest)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["vpa_experiment"])
        XCTAssertNotNil(object["source_probe"])
    }

    func testExperimentMetadataPreservesAllNativeRecorderChannelsAndSeal() throws {
        let fixture = try SourceProbeFixture(maximumSeconds: VPARequest.maximumSeconds)
        fixture.manifest.sourceProbe = nil
        fixture.manifest.prepareVPA(registrationSHA256: "synthetic")
        XCTAssertTrue(fixture.manifest.snapshotTiming.contains("window control"))
        XCTAssertTrue(vp_recorder_arm(fixture.recorder.handle, fixture.startTick))
        XCTAssertTrue(fixture.submitThreeChannels())
        XCTAssertTrue(fixture.recorder.seal())
        let result = fixture.recorder.outcome(directory: fixture.directory, expectsRender: false)
        XCTAssertEqual(result.writtenPCMBytes, 3 * 4 * 4)
        XCTAssertTrue(result.isCompleteForReference)
        XCTAssertFalse(fixture.submitThreeChannels())
    }

    func testSyntheticMaterialLoadsWithoutEngineAndKeepsFileAndNativeIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("synthetic.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128_000))
        buffer.frameLength = 128_000
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0..<128_000 { channel[index] = index.isMultiple(of: 2) ? 0.125 : -0.125 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let material = try PCMSourceMaterial.load(url: url)
        let fileHash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(material.identity.sha256, fileHash)
        XCTAssertEqual(material.buffer.frameLength, 128_000)
        XCTAssertEqual(material.identity.sourceFrameCount, 128_000)
        XCTAssertEqual(material.buffer.floatChannelData?[0][0], 0.125)
        XCTAssertEqual(material.buffer.floatChannelData?[0][1], -0.125)
        let nativeHash = SHA256.hash(data: Data(bytes: channel, count: 128_000 * 4))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(material.identity.nativePCMSHA256, nativeHash)
    }

    func testPlaybackFalseNeverReachesScoring() throws {
        let fixture = try SourceProbeFixture()
        let observer = ConfigurationChangeObserver(
            observedObject: NSObject(), recorder: fixture.recorder, center: NotificationCenter())
        var stops = 0
        XCTAssertThrowsError(
            try VPAWindow.capture(
                observer: observer, beforePlayback: {}, play: { try VPAAdmission.requirePlaybackStarted(false) },
                score: { XCTFail("No score after failed player start") },
                cleanup: (invalidate: {}, stop: { stops += 1 }))
        ) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "EXPERIMENT_PLAYBACK_FAILED")
        }
        XCTAssertEqual(stops, 1)
        XCTAssertNoThrow(try VPAAdmission.requirePlaybackStarted(true))
    }

    func testNonFloatMaterialCannotEnterPlayback() {
        let previous = identity()
        let format = NativeAudioFormat(
            sampleRate: 16_000, channelCount: 1, formatID: kAudioFormatLinearPCM,
            formatFlags: 12, bytesPerFrame: 2, bitsPerChannel: 16)
        let integer = PCMSourceIdentity(
            sha256: previous.sha256, nativePCMSHA256: previous.nativePCMSHA256, fileBytes: 256_000,
            sourceStartFrame: 0, sourceFrameCount: 128_000, nativeFormat: format)
        XCTAssertThrowsError(try VPAAdmission.validateMaterial(request: request(), identity: integer))
    }

    func testMissingStoppedStateCannotValidate() throws {
        let fixture = try SourceProbeFixture()
        XCTAssertThrowsError(try VPAAdmission.validateStopped(fixture.manifest))
    }

    func testStoppedVPFormatAndHardwareChangesAreRejected() throws {
        let fixture = try SourceProbeFixture()
        fixture.manifest.postStopState = fixture.manifest.configured.state
        fixture.manifest.postStopFormats = fixture.manifest.configured.formats
        fixture.manifest.postStopHardwareOutputFormat = fixture.manifest.hardwareOutputFormat
        try VPAAdmission.validateStopped(fixture.manifest)
        let valid = fixture.manifest
        fixture.manifest.postStopState = VoiceProcessingState(
            inputEnabled: false, outputEnabled: false, bypassed: false, agcEnabled: true, inputMuted: false)
        XCTAssertThrowsError(try VPAAdmission.validateStopped(fixture.manifest))
        let changed = identity(rate: 48_000).nativeFormat
        for field in 0..<3 {
            fixture.manifest = valid
            if field == 0 {
                fixture.manifest.postStopFormats = AudioFormats(
                    input: changed, mixer: valid.configured.formats.mixer, output: valid.configured.formats.output)
            } else if field == 1 {
                fixture.manifest.postStopFormats = AudioFormats(
                    input: valid.configured.formats.input, mixer: changed, output: changed)
            } else {
                fixture.manifest.postStopHardwareOutputFormat = changed
            }
            XCTAssertThrowsError(try VPAAdmission.validateStopped(fixture.manifest))
        }
    }
}
