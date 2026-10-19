import AVFoundation
import Foundation
@testable import VPReferenceAudio
import VPReferenceCore
import XCTest

final class ComparisonMaterialTests: XCTestCase {
    private func asset(_ name: String) throws -> URL {
        let directory = try XCTUnwrap(ProcessInfo.processInfo.environment["R2_ASSETS_DIR"])
        return URL(fileURLWithPath: directory).appendingPathComponent(name)
    }

    func testDerivedEightSecondFloatMaterialPassesOriginalAdmission() throws {
        let url = try asset("REF_resident_8s_f32.wav")
        let material = try PCMSourceMaterial.load(url: url)
        XCTAssertEqual(material.buffer.frameLength, 128_000)
        XCTAssertEqual(material.buffer.format.sampleRate, 16000)
        XCTAssertEqual(material.buffer.format.channelCount, 1)
        XCTAssertEqual(material.buffer.format.commonFormat, .pcmFormatFloat32)
        let configuration = RunConfiguration(
            mode: .enabled, durationSeconds: 16, diagnosticsArmed: true, audioExplicitlyEnabled: true,
            outputDirectory: url.deletingLastPathComponent(), materialURL: url, studyID: "offline-comparison"
        )
        let request = VPARequest(
            configuration: configuration, experimentAuthorized: true,
            targetRegistrationURL: url.deletingLastPathComponent().appendingPathComponent("NOT_READ.json"),
            materialSHA256: material.identity.sha256, nativePCMSHA256: material.identity.nativePCMSHA256
        )
        let safety = try VPAAdmission.inspectMaterial(request: request, material: material)
        XCTAssertEqual(safety.channels.count, 1)
        XCTAssertEqual(safety.channels[0].sampleCount, 128_000)
        XCTAssertLessThan(safety.channels[0].peakAbsolute, 1)
    }

    func testOriginalHostResidentParserAndDurationContract() throws {
        let source = try AppleVPAcousticWAV.read(url: asset("HOST_resident.wav"))
        XCTAssertEqual(source.sha256, "774e450ce1ff92402051f89ae4fcd537d74367deff9c2f92670ba0f6637d47ea")
        XCTAssertEqual(source.pcm.count, 228_064)
        XCTAssertTrue((144_000 ... 288_000).contains(source.pcm.count))
        XCTAssertFalse((144_000 ... 288_000).contains(384_000))
        XCTAssertThrowsError(try AppleVPAcousticWAV.read(url: asset("REF_resident_8s_f32.wav")))
    }
}
