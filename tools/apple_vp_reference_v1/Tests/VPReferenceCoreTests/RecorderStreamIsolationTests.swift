import VPRecorder
import XCTest

final class RecorderStreamIsolationTests: XCTestCase {
    func testInputAndRenderKeepIndependentFormatsAndContinuity() throws {
        let fixture = try RecorderFixture()
        try fixture.arm()
        for sample in [Int64(0), 4, 8] {
            XCTAssertTrue(fixture.submit(fixture.identity(sample: sample)))
            var render = fixture.identity(sample: sample + 120, stream: UInt32(VP_STREAM_RENDER))
            render.format.mSampleRate = 16_000
            XCTAssertTrue(fixture.submit(render))
        }
        XCTAssertTrue(vp_recorder_seal(fixture.recorder))
        let snapshot = vp_recorder_snapshot(fixture.recorder)
        XCTAssertEqual(snapshot.invalid_reasons, 0)
        XCTAssertEqual(snapshot.input_written_records, 3)
        XCTAssertEqual(snapshot.render_written_records, 3)
        XCTAssertEqual(snapshot.written_pcm_bytes, 96)
        XCTAssertEqual(snapshot.pending_records, 0)
        XCTAssertTrue(fixture.validate().complete)
    }
}
