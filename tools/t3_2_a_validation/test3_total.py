"""Independent current-Test3 Fake contract candidate; not the frozen R851 PASS."""

import hashlib
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
import run as runner

IDS = ("A1", "A2", "A3", "B1", "C1", "D1", "E1", "F1", "G1", "H1", "I1")
MANIFEST = "tools/realtime_total_regression_tests/total_invariant_manifest.tsv"
MANIFEST_SHA = "6de2ef316f6bf03b393e14549e4cd3dd6f1b0c958ad1a75e1dcec6731ddb7780"


class EvidenceMissing(ValueError):
    pass


def require(value, message):
    if not value:
        raise ValueError(message)


def static_contracts(root):
    manifest = (root / MANIFEST).read_bytes()
    require(hashlib.sha256(manifest).hexdigest() == MANIFEST_SHA,
            "Frozen invariant manifest changed")
    require(tuple(line.split("\t")[0] for line in manifest.decode().splitlines()[1:]) == IDS,
            "Frozen invariant IDs changed")
    contract = (root / "apps/macos/RuntimeCore/RealtimeResidentBrainProvider.swift").read_text()
    adapter = (root / "apps/macos/RuntimeCore/QwenRealtimeResidentBrainAdapter.swift").read_text()
    runtime = (root / "apps/macos/RuntimeCore/RuntimeCore.swift").read_text()
    aec = (root / "apps/macos/Aftelle/MacSpeechAcousticEchoHost.swift").read_text()
    tests = (root / "tools/realtime_resident_only_zero_self_interrupt_tests/"
             "RealtimeResidentOnlyZeroSelfInterruptTests.swift").read_text()
    match = re.search(r"^nonisolated struct RealtimeBrainAudioFrame: Sendable, Equatable \{"
                      r"(.*?)^\}", contract, re.MULTILINE | re.DOTALL)
    require(match is not None, "Provider PCM declaration changed")
    body = match.group(1)
    expected_fields = ["identity: RealtimeBrainSessionIdentity", "sequence: UInt64",
                       "timestampNanoseconds: UInt64", "format: RealtimeBrainAudioFormat",
                       "provenance: RealtimeBrainAudioProvenance", "bytes: Data"]
    checks = {
        "pcm_fields": re.findall(r"^    let (.+)$", body, re.MULTILINE) == expected_fields,
        "pcm_no_policy": not re.search(
            r"sourceGate|userActivity|nearEnd|playback|turn[ P]olicy|completion|backchannel|"
            r"semantic|response[ A]uthority|acoustic|eligibility", body, re.IGNORECASE),
        "provider_no_authority": not re.search(
            r"beginRealtimeBrainGenerationTransition|finishRealtimeBrainGenerationInterruption|"
            r"SessionStore|NarrativeMemory|passiveBackchannel|realtimeUserTurnDisposition|"
            r"claimRealtimeResidentBrainInterruptionDecision", adapter),
        "near_end_threshold": "static let minimumNearEndRMS = 0.012" in aec,
        "hangover": "maximumSourceGateNonUserHangoverFrames = 20" in aec,
        "completion_window": bool(re.search(
            r"private static let realtimeUtteranceCompletionWindowNanoseconds:\s*"
            r"UInt64 = 800_000_000", runtime)),
        "tail_window": "residualTailWindowNanoseconds: UInt64 = 500_000_000" in contract,
        "clear_limit": "expect(confirmedToClear <= 50_000_000," in tests,
        "first_to_clear_limit": "expect(firstToClear <= 200_000_000," in tests,
    }
    require(all(checks.values()), "Unchanged safety contract failed: " + ",".join(
        name for name, passed in checks.items() if not passed))
    return {"manifest_sha256": MANIFEST_SHA, "checks": checks, "invariant_ids": IDS}


def jobs():
    shared = "tools/realtime_resident_only_zero_self_interrupt_tests/check.sh"
    def shell(name, path, *args, seconds=180):
        return runner.job(name, ["bash", path, *args], seconds, fixture=True)
    return [shell("evidence", "tools/realtime_interruption_evidence_tests/check.sh"),
            shell("positive", shared, "r831-positive-only"),
            shell("double-talk", "tools/realtime_double_talk_acoustic_tests/check.sh"),
            shell("cross", shared, "r851-cross-node-only"),
            shell("random", shared, "r851-randomized-only"),
            shell("repeat", shared, "r851-key-repeat", seconds=900),
            shell("tool", "tools/realtime_resident_brain_tool_tests/check.sh")]


def required_metrics():
    zero_cross = ("duplicate_response_creates", "duplicate_interrupts", "duplicate_clears",
                  "stale_generation_side_effects", "false_self_interrupts",
                  "false_persistence_writes", "false_history_writes", "false_memory_writes",
                  "false_relationship_changes", "false_growth_writes", "generation_drift",
                  "lease_drift", "cross_node_failures")
    cross = {"r851_" + key: "0" for key in zero_cross}
    cross.update(r851_cross_node_executable_scenarios="12", r851_rapid_consecutive_turns="20",
                 r851_repeated_interruption_cycles="10", r851_stop_restart_points="5",
                 r851_delayed_provider_ordering_cases="6", realtime_total_cross_node="PASS")
    random = {"r851_randomized_" + key: "0" for key in (
        "race_failures", "duplicate_response_creates", "false_self_interrupts",
        "false_persistence_writes", "generation_drift", "lease_drift")}
    random.update(r851_randomized_race_iterations="100", r851_randomized_seed="0x851511A7",
                  r851_randomized_generation_transitions_expected="9",
                  r851_randomized_generation_transitions_observed="9",
                  realtime_total_randomized="PASS")
    positive = {"r831_" + key: "0" for key in (
        "confirmed_interruptions", "provider_interrupts", "provider_cancels",
        "host_playback_clears", "generation_changes", "lease_changes", "false_history_writes",
        "false_memory_writes", "relationship_changes")}
    positive.update(r831_positive_control_acoustic_eligibility="1",
                    realtime_true_near_end_opening="PASS")
    return {
        "evidence": {"realtime_interruption_evidence_identity_fence": "PASS",
                     "realtime_interruption_host_execution_only": "PASS",
                     "realtime_interruption_qwen_proposal_only": "PASS"},
        "positive": positive,
        "double-talk": {"realtime_double_talk_acoustic": "PASS"},
        "cross": cross, "random": random,
        "repeat": {"r851_key_suite_repeat_runs": "15", "r851_key_suite_repeat_subprocesses": "18",
                   "r851_key_suite_repeat_failures": "0", "realtime_total_key_repeat": "PASS"},
        "tool": {"realtime_resident_brain_tool_cases": "7",
                 "realtime_resident_brain_tool_checks": "143",
                 "realtime_resident_brain_tool_runtime_ownership": "PASS",
                 "realtime_resident_brain_tool_provider_execution_bypass": "PASS",
                 "realtime_resident_brain_tool_parallel_system": "PASS",
                 "realtime_resident_brain_tool_network_dependency": "ZERO"},
    }


def validate_metrics(observed):
    for name, required in required_metrics().items():
        for key, expected in required.items():
            if name not in observed or key not in observed[name]:
                raise EvidenceMissing(name + "/" + key)
            require(observed[name][key] == expected, name + "/" + key + " invariant failed")
    for template in ("final_before_stop", "completion_before_final", "partial_final_stop",
                     "short_pause_resume", "provider_first_start"):
        key = "r851_randomized_" + template
        if key not in observed["random"]:
            raise EvidenceMissing(key)
        require(int(observed["random"][key]) > 0, key + " was not executed")


def read_metrics(rows):
    observed = {}
    for row in rows:
        if row["status"] != "PASS" or row["exit_code"] != 0:
            raise EvidenceMissing(row["name"] + " did not pass")
        data = Path(row["log"]).read_bytes()
        require(hashlib.sha256(data).hexdigest() == row["log_sha256"], "Log tampering")
        observed[row["name"]] = dict(re.findall(
            r"^([A-Za-z][A-Za-z0-9_]*)=([^\r\n]+)$", data.decode(errors="replace"), re.MULTILINE))
    return observed


def main(directory):
    os.umask(0o077)
    directory = directory.resolve()
    if not directory.is_relative_to((runner.ROOT / ".build/t3_2_a_validation").resolve()):
        raise ValueError("Candidate output must be inside the ignored validation directory")
    directory.mkdir(mode=0o700)
    before = runner.identity()
    rows, guards, observed = [], {}, {}
    status, reason = "BLOCKED", "Fixed offline fixture missing"
    try:
        if not runner.FIXTURE.is_file():
            raise EvidenceMissing(reason)
        guards = static_contracts(runner.ROOT)
        rows = runner.run_jobs(jobs(), runner.ROOT, directory, {}, before)
        if any(row["status"] == "FAIL" for row in rows):
            status, reason = "FAIL", "Existing invariant execution failed; stop without repair"
        else:
            observed = read_metrics(rows)
            validate_metrics(observed)
            runner.require_same_identity(before, runner.identity())
            status, reason = "PASS", "TEST3_CANDIDATE_PASS"
    except EvidenceMissing as error:
        status, reason = "BLOCKED", str(error)
    except (AssertionError, ValueError) as error:
        status, reason = "FAIL", str(error)
    for row in rows:
        row["source_commit"] = before["source_commit"]
    report = {"schema_version": 1, "candidate": "TEST3_CURRENT_FAKE_CONTRACTS_V0.2",
              "scope": "Runtime/Fake safety contracts; not Apple acoustic source qualification",
              "identity": before, "status": status, "reason": reason, "tests": rows,
              "guards": guards, "observed_metrics": observed,
              "invariants": {key: status for key in IDS},
              "legacy_R851_approval": "UNCHANGED; no frozen baseline bypass",
              "approval": "FULL_APPROVAL_PENDING", "R3_M01": "OPEN",
              "Test3.execution_authorized": False}
    runner.write_report(directory / "results.json", report)
    print(reason, flush=True)
    print("test3_candidate_invariants=" + str(len(IDS)))
    print("test3_candidate_status=" + status)
    return {"PASS": 0, "FAIL": 1, "BLOCKED": 2}[status]


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1])))
