import Foundation
import CoreAudio
@main struct VADTests {
    static func main() throws {
        let detector = SystemMacSpeechVoiceActivityDetector()
        var rows: [[String: Any]] = []
        func record(_ name: String, _ expected: Bool) {
            let actual = detector.isVoiceDetected()
            rows.append(["name": name, "expected": expected, "actual": actual, "pass": expected == actual])
        }
        FakeHAL.state = 0; precondition(detector.start()); record("initial_false", false)
        FakeHAL.state = 1; detector.auditRefreshForTesting(); record("notification_true", true)
        detector.auditRefreshForTesting(); record("repeat_state_true", true)
        FakeHAL.state = nil; detector.auditRefreshForTesting(); record("read_failure_invalidates_previous_true", false)
        FakeHAL.state = 1; detector.auditRefreshForTesting(); record("successful_read_recovers", true)
        FakeHAL.state = 0; detector.auditRefreshForTesting(); record("notification_false", false)
        FakeHAL.state = 1; detector.auditRefreshForTesting(); detector.stop(); record("stop_clears_true", false)
        detector.auditRefreshForTesting(); record("stopped_callback_cannot_restore", false)
        FakeHAL.state = 0; precondition(detector.start()); record("restart_reads_fresh_initial_state", false); detector.stop()
        FakeHAL.supported = false; rows.append(["name":"unsupported_start_rejected","pass":!detector.start()]); record("unsupported_false", false)
        FakeHAL.supported = true; FakeHAL.setSuccess = false; rows.append(["name":"enable_failure_rejected","pass":!detector.start()]); FakeHAL.setSuccess = true
        FakeHAL.listenerStatus = -1; rows.append(["name":"listener_failure_rejected","pass":!detector.start()]); FakeHAL.listenerStatus = 0
        FakeHAL.state = 1; precondition(detector.start()); record("initial_true", true); detector.stop()
        let host = MacSpeechAcousticEchoHost(mode: .appleVoiceProcessing); _ = host.configure()
        FakeHAL.state = 1; precondition(detector.start())
        FakeHAL.state = nil; detector.auditRefreshForTesting()
        host.updateSystemVoiceActivity(detector.isVoiceDetected())
        let samples = (0..<480).map { Float(sin(Double($0) * 0.1) * 0.05) }
        let spans = host.processCaptureSpans(samples, hostTimeNanoseconds: 1_000_000_000)
        let activity = MacSpeechAudioActivityEvidenceKind.classify(observation: spans[0].observation)
        rows.append(["name":"read_failure_must_not_authorize_listening_audio","activity":activity.rawValue,"pass":activity != .listeningNearEnd])
        detector.stop()
        FakeHAL.state = 1; precondition(detector.start())
        FakeHAL.onStateRead = {
            detector.stop()
            FakeHAL.state = 0
            precondition(detector.start())
        }
        detector.auditRefreshForTesting()
        record("same_device_restart_rejects_inflight_old_read", false)
        detector.stop()
        for (name, oldState) in [("old_failed_read_cannot_clear_restarted_true", Optional<UInt32>.none), ("old_successful_false_cannot_clear_restarted_true", Optional<UInt32>.some(0))] {
            let detector = SystemMacSpeechVoiceActivityDetector()
            FakeHAL.enabled = 0; FakeHAL.state = 1; precondition(detector.start())
            FakeHAL.state = oldState
            FakeHAL.onStateRead = {
                detector.stop()
                FakeHAL.state = 1
                precondition(detector.start())
            }
            detector.auditRefreshForTesting()
            let actual = detector.isVoiceDetected()
            rows.append(["name":name,"expected":true,"actual":actual,"pass":actual])
            detector.stop()
        }
        let result: [String: Any] = ["schema_version":1,"HAL_is_fake":true,"tests":rows,"passed":rows.filter{($0["pass"] as? Bool)==true}.count,"failed":rows.filter{($0["pass"] as? Bool)==false}.count]
        let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]));print(String(decoding:data,as:UTF8.self)); precondition(rows.allSatisfy { $0["pass"] as? Bool == true })
    }
}
