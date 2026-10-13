import Foundation
import VPReferenceCore
import XCTest

final class ConfigurationTests: XCTestCase {
    func testOffDisablesBothNodesInStoppedState() throws {
        let driver = FakeEngineDriver()
        let configured = try ConfigurationPlan.configure(mode: .disabled, driver: driver)
        XCTAssertFalse(configured.state.inputEnabled)
        XCTAssertFalse(configured.state.outputEnabled)
        XCTAssertEqual(driver.operations, ["set:false", "state", "formats", "connect", "formats"])
    }

    func testOnEnablesBothNodesAndReadsFormatsAfterConfiguration() throws {
        let driver = FakeEngineDriver()
        let configured = try ConfigurationPlan.configure(mode: .enabled, driver: driver)
        XCTAssertTrue(configured.state.inputEnabled)
        XCTAssertTrue(configured.state.outputEnabled)
        XCTAssertEqual(configured.formats, configured.preConnectionFormats)
        XCTAssertEqual(driver.operations, ["set:true", "state", "formats", "connect", "formats"])
    }

    func testRunningEngineCannotBeReconfigured() {
        let driver = FakeEngineDriver()
        driver.isRunning = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: driver))
        XCTAssertTrue(driver.operations.isEmpty)
    }

    func testUnsupportedDeviceAndUnavailableStateFail() {
        let unsupported = FakeEngineDriver()
        unsupported.unsupported = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: unsupported))
        let unavailable = FakeEngineDriver()
        unavailable.unavailable = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: unavailable))
    }

    func testBypassIsNotDisabledAndOutputStateMustMatch() {
        let driver = FakeEngineDriver()
        driver.wrongOutput = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .disabled, driver: driver))
        let bypassed = FakeEngineDriver()
        bypassed.bypassed = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: bypassed))
    }

    func testFormatChangesAndInvalidNativeFormatsFail() {
        let changing = FakeEngineDriver()
        changing.changeFormats = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: changing))
        let invalid = FakeEngineDriver()
        invalid.invalidFormat = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .disabled, driver: invalid))
    }

    func testOnRejectsDifferentIOFormats() {
        let driver = FakeEngineDriver()
        driver.differentOutput = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: driver))
    }

    func testMixerNegotiationUsesFreshFinalFormat() throws {
        let driver = FakeEngineDriver()
        driver.mixerNegotiates = true
        let configured = try ConfigurationPlan.configure(mode: .enabled, driver: driver)
        XCTAssertEqual(configured.formats.input, configured.preConnectionFormats.input)
        XCTAssertNotEqual(configured.formats.mixer, configured.preConnectionFormats.mixer)
        XCTAssertEqual(configured.preConnectionFormats.mixer.sampleRate, 16_000)
        XCTAssertEqual(configured.formats.mixer, configured.formats.output)
    }

    func testEveryConfigurationUsesItsOwnDriver() throws {
        let first = FakeEngineDriver()
        let second = FakeEngineDriver()
        _ = try ConfigurationPlan.configure(mode: .disabled, driver: first)
        _ = try ConfigurationPlan.configure(mode: .enabled, driver: second)
        XCTAssertFalse(first.enabled)
        XCTAssertTrue(second.enabled)
    }

    func testUnavailablePropertiesHaveExplicitEvidenceStatus() throws {
        let state = VoiceProcessingState(
            inputEnabled: false, outputEnabled: false,
            bypassed: nil, agcEnabled: nil, inputMuted: nil
        )
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["bypassStatus"] as? String, "UNAVAILABLE")
        XCTAssertEqual(json["agcStatus"] as? String, "UNAVAILABLE")
        XCTAssertEqual(json["muteStatus"] as? String, "UNAVAILABLE")
        XCTAssertEqual(try JSONDecoder().decode(VoiceProcessingState.self, from: data), state)
    }
}

private final class FakeEngineDriver: EngineConfigurationDriving {
    var isRunning = false
    var enabled = false
    var unsupported = false
    var unavailable = false
    var wrongOutput = false
    var bypassed = false
    var changeFormats = false
    var invalidFormat = false
    var differentOutput = false
    var mixerNegotiates = false
    var operations: [String] = []
    private var reads = 0

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        operations.append("set:\(enabled)")
        if unsupported { throw ReferenceFailure.blocked("Synthetic unsupported device") }
        self.enabled = enabled
    }

    func readVoiceProcessingState() throws -> VoiceProcessingState {
        operations.append("state")
        return VoiceProcessingState(
            inputEnabled: enabled, outputEnabled: wrongOutput ? !enabled : enabled,
            bypassed: unavailable ? nil : bypassed, agcEnabled: unavailable ? nil : true,
            inputMuted: unavailable ? nil : false
        )
    }

    func readFormats() throws -> AudioFormats {
        operations.append("formats")
        reads += 1
        let rate = invalidFormat ? 0 : (changeFormats && reads > 1 ? 44_100 : 48_000.0)
        let format = makeFormat(rate: rate)
        return AudioFormats(
            input: format, mixer: mixerNegotiates && reads == 1 ? makeFormat(rate: 16_000) : format,
            output: differentOutput ? makeFormat(rate: 16_000) : format
        )
    }

    func connectPlayback(using formats: AudioFormats) throws {
        operations.append("connect")
    }

    private func makeFormat(rate: Double) -> NativeAudioFormat {
        NativeAudioFormat(
            sampleRate: rate, channelCount: 2, formatID: 0x6C70_636D,
            formatFlags: 9, bytesPerFrame: 8, bitsPerChannel: 32
        )
    }
}
