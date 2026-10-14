import Foundation
import XCTest

@testable import VPReferenceCore

final class VPFormatNegotiationTests: XCTestCase {
    func testOnNegotiatesInitialDifferentClientFormatsBeforeStrictValidation() throws {
        let driver = FormatNegotiationDriver()
        let configured = try ConfigurationPlan.configure(mode: .enabled, driver: driver)
        XCTAssertNotEqual(configured.preConnectionFormats.input, configured.preConnectionFormats.output)
        XCTAssertEqual(configured.formats.input, configured.formats.output)
        XCTAssertEqual(configured.formats.input.channelCount, 3)
        XCTAssertEqual(driver.enableCalls, 1)
        XCTAssertEqual(driver.connectCalls, 1)
    }

    func testOnStillRejectsMismatchAfterConnection() {
        let driver = FormatNegotiationDriver()
        driver.keepMismatch = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: driver)) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "VP_IO_FORMAT_MISMATCH")
        }
        XCTAssertEqual(driver.enableCalls, 1)
        XCTAssertEqual(driver.connectCalls, 1)
    }

    func testOffKeepsItsOwnOutputClientFormat() throws {
        let driver = FormatNegotiationDriver()
        let configured = try ConfigurationPlan.configure(mode: .disabled, driver: driver)
        XCTAssertEqual(configured.preConnectionFormats.output, configured.formats.output)
        XCTAssertNotEqual(configured.formats.input, configured.formats.output)
    }

    func testOnCannotChangeInputToHideMismatch() {
        let driver = FormatNegotiationDriver()
        driver.changeInput = true
        XCTAssertThrowsError(try ConfigurationPlan.configure(mode: .enabled, driver: driver)) { error in
            XCTAssertEqual((error as? EngineeringFailure)?.diagnostic.code, "INPUT_FORMAT_CHANGED")
        }
    }
}

private final class FormatNegotiationDriver: EngineConfigurationDriving {
    var isRunning = false
    var keepMismatch = false
    var changeInput = false
    var enableCalls = 0
    var connectCalls = 0
    private var enabled = false
    private var connected = false

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        enableCalls += 1
        self.enabled = enabled
    }

    func readVoiceProcessingState() throws -> VoiceProcessingState {
        VoiceProcessingState(
            inputEnabled: enabled, outputEnabled: enabled, bypassed: false,
            agcEnabled: enabled, inputMuted: false)
    }

    func readFormats() throws -> AudioFormats {
        let input = format(rate: connected && changeInput ? 48_000 : 16_000, channels: 3)
        let output = connected && enabled && !keepMismatch ? input : format(rate: 44_100, channels: 2)
        return AudioFormats(input: input, mixer: output, output: output)
    }

    func connectPlayback(using formats: AudioFormats) throws {
        connectCalls += 1
        connected = true
    }

    private func format(rate: Double, channels: UInt32) -> NativeAudioFormat {
        NativeAudioFormat(
            sampleRate: rate, channelCount: channels, formatID: 0x6C70_636D,
            formatFlags: 41, bytesPerFrame: 4, bitsPerChannel: 32)
    }
}
