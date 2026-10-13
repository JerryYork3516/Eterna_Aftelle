#!/usr/bin/env python3
"""Non-device checks over the explicitly synthetic --ledger-only artifacts."""
import copy
import json
from pathlib import Path
import sys

import inspect_ledger as ledger

CHECKS = 0


def check(value, message):
    global CHECKS
    CHECKS += 1
    assert value, message


def load(directory, filename):
    data = (directory / filename).read_bytes()
    records = [dict(zip(ledger.SCALAR.FIELDS, ledger.SCALAR.RECORD.unpack_from(data, offset)))
               for offset in range(0, len(data), ledger.SCALAR.RECORD.size)]
    return records[1:-1], records[-1]


def check_pipeline(result):
    check(result["validity"] == "NOMINAL_RESAMPLE", "complete logical ledger is not FIR truth")
    check(len(result["gate_sources"]) == 32, "32 clean48 sources")
    check(all(g["terminal"] == "HOST_RETURNED" for g in result["gate_sources"]), "actual Host return")
    check(all(g["aec_internal_epoch"] == "UNVERIFIED" for g in result["gate_sources"]), "no O2 inference")
    check(len(result["packets"]) == 14, "actual packet count")
    check({p["terminal"] for p in result["packets"]} == {"DRAINED", "DROP_OLDEST", "CLEARED"}, "queue terminals")
    check({p["generation"] for p in result["packets"]} == {7, 8}, "generation retained")
    check(all(p["sample_ledger"] == "EXACT_LEDGER" for p in result["packets"]), "exact float24 packet ledger")
    check(all(p["encoding_event_id"] for p in result["packets"]), "actual encoding linked")
    check(all(sum(f["float24_interval"][1] - f["float24_interval"][0] for f in p["fragments"]) == 480
              for p in result["packets"]), "480-sample coverage without holes")
    check(all(f["nominal_parent_fragments"] for p in result["packets"] for f in p["fragments"]), "upstream fragments")
    check(any(len(p["fragments"]) > 2 for p in result["packets"]), "stateful converter does not always return 240")
    check(all(c["internal_consumption"] == "DSP_SUPPORT_UNVERIFIED" for c in result["conversions"]), "submission not consumption")
    check(all(s["ownership"] == "SUBMITTED" for s in result["host_input_ownership"]), "every returned source submitted")
    check(bool(result["discarded_packetizer_ranges"]), "generation/deinit tail accounted")
    check(result["physical_human_source"] == "UNVERIFIED", "synthetic input cannot certify humans")


def check_faults(directory, manifest, results):
    gate = results["gate"]["gate_sources"]
    real = [g for g in gate if g["validity"] == "EXACT_LEDGER"]
    check(len(real) == 2, "only actual Host Gate calls have proven AEC ancestry")
    check({g["active_zero"] for g in real} == {False, True}, "zero PCM PASS versus active ZERO")
    check(results["gate"]["validity"] == "INVALID", "isolated Gate fixtures never invent AEC ancestry")
    check(results["cross_run"]["validity"] == "INVALID", "pre-arm retained source is unknown")
    check(results["cross_run"]["gate_sources"][0]["source_event_id"] is None, "no replacement source ID")
    host = results["host_failure"]["gate_sources"][0]
    check(host["terminal"] == "DISCARD" and not host["host_return_events"], "provisional output lost at whole-batch fallback")
    check(host["host_call_status"] == 6, "actual failure status")
    packet = results["packets"]["packets"][0]
    check(len(packet["fragments"]) == 2, "two direct 10ms float24 fragments")
    check({f["representative_gate_open"] for f in packet["fragments"]} == {True, False}, "mixed qualification preserved")
    check(packet["sample_ledger"] == "EXACT_LEDGER", "direct packet sample accounting")
    check(results["packets"]["validity"] == "INVALID", "missing upstream conversion not fabricated")
    check(results["packets"]["discarded_packetizer_ranges"][0]["float24_interval"] == [480, 497], "reset discards 17")
    check(results["packets"]["pending_packetizer_ranges"][0]["float24_interval"] == [0, 23], "seal pending 23")
    encoding = results["packets"]["encoding_events"]
    check(any(e["kind"] == 17 and e["detail"] == 2 and e["reserved"] == 1 for e in encoding), "encoding counters")
    check([(e["status"], e["inputStart"], e["inputEnd"]) for e in encoding if e["kind"] == 24]
          == [(1, 0, 2), (2, 2, 3)], "exact nonfinite and quantization-zero ranges")
    failed = results["conversion"]
    check(any(p["terminal"] == "DISCARD_BATCH_FAILURE" for p in failed["packets"]), "partial packet never delivered")
    check(any(c["terminal"] == "INVALID_CONVERSION_OR_UNRETURNED_OUTPUT" for c in failed["conversions"]), "throw output explicit")
    check(bool(failed["duplicate_source_submissions"]), "resubmitted same Host source detected")
    check(failed["validity"] == "INVALID", "duplicate source cannot claim unique ownership")
    check(any(s["ownership"] == "INVALID" and not s["conversion_events"] for s in failed["host_input_ownership"]), "unvisited sources after throw not omitted")
    resumed, _ = load(directory, manifest["converter_resumed"])
    check(any(e["kind"] == 13 and e["flags"] & 128 for e in resumed), "earlier-run FIR phase unknown")
    check(results["converter_resumed"]["validity"] == "INVALID", "earlier-run ancestry not fabricated")
    mixed = results["mixed"]
    check(mixed["validity"] == "NOMINAL_RESAMPLE", "real Gate and converter logical join")
    check({g["active_zero"] for g in mixed["gate_sources"]} == {False, True}, "mixed PASS/ZERO Gate sources")
    check(len(mixed["packets"][0]["fragments"]) == 3, "all actual float24 fragments")
    check(len({p["host_return_event_id"] for f in mixed["packets"][0]["fragments"]
               for p in f["nominal_parent_fragments"]}) == 2, "nominal ancestry differs from append provenance")
    queue = results["buffer"]
    check({q["terminal"] for q in queue["queue_entries"]} == {"DROP_OLDEST", "CLEARED", "DRAINED"}, "all buffer terminals")
    check(len(queue["queue_rejections"]) == 1, "rejected stale generation")
    for name in ("overflow", "pending"):
        check(not results[name]["recorder_valid"] and results[name]["validity"] == "INVALID", name)
    events, footer = load(directory, manifest["pipeline"])
    check_mutations(events, footer)


def check_mutations(events, footer):
    def changed(kind, key, transform):
        mutant = copy.deepcopy(events)
        target = next(e for e in mutant if e["kind"] == kind)
        target[key] = transform(target[key])
        return ledger.reconcile(mutant, footer)

    check(changed(9, "parent", lambda _: 0)["validity"] == "INVALID", "missing AEC parent")
    check(changed(9, "reserved", lambda x: x + 99999)["validity"] == "INVALID", "broken source key")
    check(changed(15, "inputStart", lambda x: x + 1)["validity"] == "INVALID", "fragment hole")
    check(changed(16, "inputEnd", lambda x: x - 1)["validity"] == "INVALID", "truncated packet")
    check(changed(17, "frameCount", lambda x: x - 1)["validity"] == "INVALID", "encoding mismatch")
    check(changed(20, "outputEnd", lambda x: x + 1)["validity"] == "INVALID", "delivery count mismatch")
    duplicate = copy.deepcopy(events)
    duplicate.append(copy.deepcopy(next(e for e in events if e["kind"] == 9)))
    check(ledger.reconcile(duplicate, footer)["validity"] == "INVALID", "duplicate ticket")
    duplicate[-1]["id"] = max(e["id"] for e in events) + 1
    check(ledger.reconcile(duplicate, footer)["validity"] == "INVALID", "duplicate source different ticket")
    no_state = [e for e in events if not (e["kind"] == 11 and not e["flags"] & 16)]
    check(ledger.reconcile(no_state, footer)["validity"] == "INVALID", "missing action state")
    no_gate = [e for e in events if e["kind"] != 9]
    check(ledger.reconcile(no_gate, footer)["validity"] == "INVALID", "missing Gate origin")
    no_encoding = [e for e in events if e["kind"] != 17]
    check(ledger.reconcile(no_encoding, footer)["validity"] == "INVALID", "missing encoder")
    no_host = [e for e in events if e["kind"] != 12]
    check(ledger.reconcile(no_host, footer)["validity"] == "INVALID", "missing Host final return")
    missing_return = copy.deepcopy(events)
    missing_return.remove(next(e for e in missing_return if e["kind"] == 12 and not e["flags"] & 8))
    check(ledger.reconcile(missing_return, footer)["validity"] == "INVALID", "Host summary detects missing returned span")
    terminal = copy.deepcopy(next(e for e in events if e["kind"] == 19 and e["status"] == 9))
    terminal["id"] = max(e["id"] for e in events) + 1
    check(ledger.reconcile(events + [terminal], footer)["validity"] == "INVALID", "double queue terminal")
    for key in ("flags", "detail", "remainderAfter"):
        invalid_footer = {**footer, key: 1}
        result = ledger.reconcile(events, invalid_footer)
        check(result["validity"] == "INVALID", "global integrity override " + key)
        check(all(p["sample_ledger"] == "INVALID" for p in result["packets"]), "no partial PASS " + key)
        check(all(f["upstream_validity"] == "INVALID" for p in result["packets"] for f in p["fragments"]),
              "no nominal ancestry acceptance after recorder failure " + key)


def main():
    directory = Path(sys.argv[1])
    manifest = json.loads((directory / "ledger-artifacts.json").read_text())
    results = {name: ledger.inspect(directory / filename) for name, filename in manifest.items()}
    check_pipeline(results["pipeline"])
    check_faults(directory, manifest, results)
    for name, result in results.items():
        (directory / ("reconciled-" + name + ".json")).write_text(json.dumps(result, indent=2) + "\n")
    print(f"step2b_ledger_checks={CHECKS} synthetic_scalar_only=true")


if __name__ == "__main__":
    main()
