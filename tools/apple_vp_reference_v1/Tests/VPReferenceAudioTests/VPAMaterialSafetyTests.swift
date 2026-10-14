import AVFoundation
import Foundation
import VPReferenceCore
import XCTest

@testable import VPReferenceAudio

final class VPAMaterialSafetyTests: XCTestCase {
    private func buffer(_ samples: [[Float]], interleaved: Bool = false) throws -> AVAudioPCMBuffer {
        let layout = try XCTUnwrap(
            AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(samples.count)))
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, interleaved: interleaved, channelLayout: layout)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples[0].count)))
        buffer.frameLength = buffer.frameCapacity
        let data = try XCTUnwrap(buffer.floatChannelData)
        for channel in samples.indices {
            for frame in samples[channel].indices { data[channel][frame * buffer.stride] = samples[channel][frame] }
        }
        return buffer
    }

    private func request(material: PCMSourceMaterial) -> VPARequest {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return VPARequest(
            configuration: RunConfiguration(
                mode: .enabled, durationSeconds: 16, diagnosticsArmed: true, audioExplicitlyEnabled: true,
                outputDirectory: root.appendingPathComponent("run"),
                materialURL: root.appendingPathComponent("sound.caf"),
                studyID: "synthetic-safety"), experimentAuthorized: true,
            targetRegistrationURL: root.appendingPathComponent("absent-registration.json"),
            materialSHA256: material.identity.sha256, nativePCMSHA256: material.identity.nativePCMSHA256)
    }

    private func material(sample: Float) throws -> PCMSourceMaterial {
        let value = try buffer([Array(repeating: sample, count: 128_000)])
        return PCMSourceMaterial(
            buffer: value,
            identity: PCMSourceIdentity(
                sha256: String(repeating: "a", count: 64), nativePCMSHA256: String(repeating: "b", count: 64),
                fileBytes: 512_000, sourceStartFrame: 0, sourceFrameCount: 128_000,
                nativeFormat: AppleEngineDriver.snapshot(value.format)))
    }

    func testPlanarChannelsReportSeparatePeaksAndBothSignedFullScaleCounts() throws {
        let value = try buffer([[0, 1, -1, 0.5], [-0.25, 0, -0.75, 0], [1, 1, 1, -1]])
        let result = try VPAMaterialSafety.inspect(value)
        XCTAssertEqual(result.channels.map(\.index), [0, 1, 2])
        XCTAssertEqual(result.channels.map(\.sampleCount), [4, 4, 4])
        XCTAssertEqual(result.channels.map(\.peakAbsolute), [1, 0.75, 1])
        XCTAssertEqual(result.channels.map(\.fullScaleSampleCount), [2, 0, 4])
    }

    func testInterleavedStrideChecksEveryChannelIncludingLastSample() throws {
        let value = try buffer([[0.1, -0.3, 0.2], [0.8, 0.4, -1]], interleaved: true)
        let result = try VPAMaterialSafety.inspect(value)
        XCTAssertEqual(result.channels.map(\.peakAbsolute), [0.3, 1])
        XCTAssertEqual(result.channels.map(\.fullScaleSampleCount), [0, 1])
    }

    func testNaNAndBothInfinitiesAreRejectedInEachPlanarChannel() throws {
        for channel in 0..<3 {
            for invalid: Float in [.nan, .infinity, -.infinity] {
                var samples = Array(repeating: Array(repeating: Float(0), count: 4), count: 3)
                samples[channel][3] = invalid
                let value = try buffer(samples)
                XCTAssertThrowsError(try VPAMaterialSafety.inspect(value)) { error in
                    XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "MATERIAL_NON_FINITE_SAMPLES")
                }
            }
        }
    }

    func testOutOfRangeRejectsNextFloatPastBothBoundariesAndLargerValues() throws {
        for invalid: Float in [Float(1).nextUp, Float(-1).nextDown, 2, -2, .greatestFiniteMagnitude] {
            let value = try buffer([[0, invalid]])
            XCTAssertThrowsError(try VPAMaterialSafety.inspect(value)) { error in
                XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "MATERIAL_OUT_OF_RANGE_SAMPLES")
            }
        }
    }

    func testInterleavedUnsafeNonFirstChannelCannotBeSkipped() throws {
        for invalid: Float in [.nan, .infinity, Float(-1).nextDown] {
            let value = try buffer([[0, 0, 0], [0, 0, invalid]], interleaved: true)
            XCTAssertThrowsError(try VPAMaterialSafety.inspect(value))
        }
    }

    func testSilenceAndValuesImmediatelyInsideFullScaleAreAccepted() throws {
        let value = try buffer([[0, -0.0], [Float(1).nextDown, Float(-1).nextUp]])
        let result = try VPAMaterialSafety.inspect(value)
        XCTAssertEqual(result.channels[0].peakAbsolute, 0)
        XCTAssertEqual(result.channels[1].peakAbsolute, Float(1).nextDown)
        XCTAssertEqual(result.channels.map(\.fullScaleSampleCount), [0, 0])
    }

    func testInspectionDoesNotNormalizeOrModifyAnySample() throws {
        let samples: [[Float]] = [[-1, 0.25, 0.75, 1], [0.5, -0.5, 0, -0.0]]
        for interleaved in [false, true] {
            let value = try buffer(samples, interleaved: interleaved)
            _ = try VPAMaterialSafety.inspect(value)
            let data = try XCTUnwrap(value.floatChannelData)
            for channel in samples.indices {
                for frame in samples[channel].indices {
                    XCTAssertEqual(data[channel][frame * value.stride].bitPattern, samples[channel][frame].bitPattern)
                }
            }
        }
    }

    func testEmptyAndIntegerBuffersFailWithoutScanning() throws {
        let value = try buffer([[0]])
        value.frameLength = 0
        XCTAssertThrowsError(try VPAMaterialSafety.inspect(value))
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let integer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        integer.frameLength = 1
        XCTAssertThrowsError(try VPAMaterialSafety.inspect(integer))
    }

    func testOversizedSyntheticBufferIsRejectedBeforeScanning() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let value = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_097_153))
        value.frameLength = value.frameCapacity
        XCTAssertThrowsError(try VPAMaterialSafety.inspect(value)) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "MATERIAL_SAMPLE_LAYOUT_INVALID")
        }
    }

    func testTooManyChannelsAreRejectedBeforeScanning() throws {
        let value = try buffer(Array(repeating: [0], count: 33))
        XCTAssertThrowsError(try VPAMaterialSafety.inspect(value))
    }

    func testRealAdmissionRejectsUnsafeBufferBeforeRegistrationOrDeviceReads() throws {
        for sample: Float in [.nan, 2] {
            let value = try material(sample: sample)
            let request = request(material: value)
            XCTAssertThrowsError(try VPAAdmission.prepare(request: request, material: value)) { error in
                let code = (error as? EngineeringFailure)?.diagnostic.code
                XCTAssertEqual(code, sample.isNaN ? "MATERIAL_NON_FINITE_SAMPLES" : "MATERIAL_OUT_OF_RANGE_SAMPLES")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: request.configuration.outputDirectory.path))
        }
    }

    func testMaterialIdentityFailurePrecedesSampleInspection() throws {
        let unsafe = try material(sample: .nan)
        let valid = try material(sample: 0.25)
        let changed = PCMSourceMaterial(
            buffer: unsafe.buffer,
            identity: PCMSourceIdentity(
                sha256: "changed", nativePCMSHA256: valid.identity.nativePCMSHA256, fileBytes: 512_000,
                sourceStartFrame: 0, sourceFrameCount: 128_000, nativeFormat: valid.identity.nativeFormat))
        let configuration = request(material: valid)
        XCTAssertThrowsError(try VPAAdmission.inspectMaterial(request: configuration, material: changed)) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "MATERIAL_IDENTITY_MISMATCH")
        }
    }

    func testValidMaterialSummaryIsEncodedOnlyInPrivateVPAEvidence() throws {
        let value = try material(sample: 0.25)
        let summary = try VPAAdmission.inspectMaterial(request: request(material: value), material: value)
        let fixture = try SourceProbeFixture()
        XCTAssertNil(fixture.manifest.vpaExperiment)
        fixture.manifest.prepareVPA(registrationSHA256: "synthetic", materialSafety: summary)
        let data = try JSONEncoder().encode(fixture.manifest)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let experiment = try XCTUnwrap(object["vpa_experiment"] as? [String: Any])
        let safety = try XCTUnwrap(experiment["materialSafety"] as? [String: Any])
        let channels = try XCTUnwrap(safety["channels"] as? [[String: Any]])
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0]["sampleCount"] as? Int, 128_000)
        XCTAssertEqual(channels[0]["peakAbsolute"] as? Double, 0.25)
        XCTAssertEqual(channels[0]["fullScaleSampleCount"] as? Int, 0)
    }
}
