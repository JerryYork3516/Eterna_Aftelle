#!/usr/bin/env python3
"""Offline O3/O4 scalar reconciliation. No audio decoder or physical-source claim."""
import argparse
import importlib.util
import json
from collections import defaultdict
from fractions import Fraction
from pathlib import Path
import struct

SPEC = importlib.util.spec_from_file_location("ace3_scalar_inspect", Path(__file__).with_name("inspect.py"))
SCALAR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCALAR)
ACTIONS = {1: "PASS", 2: "RETAIN", 3: "RELEASE", 4: "ZERO", 5: "RESET_REMOVAL"}


def source_key(event):
    return event["object"], event["detail"], event["reserved"], event["contentTime"]


def snapshot_key(event):
    return event["detail"], event["reserved"], event["contentTime"]


def inside(child, parent):
    return (child["thread"] == parent["thread"] and
            parent["entered"] <= child["entered"] <= child["completed"] <= parent["completed"])


def one(values):
    return values[0] if len(values) == 1 else None


def classify_gates(events):
    births = defaultdict(list)
    actions = defaultdict(list)
    outputs = defaultdict(list)
    frames = {e["id"]: e for e in events if e["kind"] == 4}
    summaries = {e["parent"]: e for e in events if e["kind"] == 12 and e["flags"] & 8}
    decisions = defaultdict(list)
    states = {e["parent"]: e for e in events if e["kind"] == 11 and not e["flags"] & 16 and e["parent"]}
    for event in events:
        key = source_key(event)
        if event["kind"] == 9:
            births[key].append(event)
        elif event["kind"] == 10:
            actions[key].append(event)
        elif event["kind"] == 12 and not event["flags"] & 8:
            outputs[key].append(event)
        elif event["kind"] == 11 and event["flags"] & 16:
            decisions[key].append(event)
    result = []
    for key in sorted(set(births) | set(actions) | set(outputs)):
        birth = one(births[key])
        frame = frames.get(birth["parent"]) if birth else None
        trace = sorted(actions[key], key=lambda e: e["id"])
        returned = outputs[key]
        valid = (birth is not None and frame is not None and frame["stream"] == 1 and
                 not birth["flags"] & 1024 and frame["status"] == 0 and
                 birth["frameCount"] == frame["inputEnd"] - frame["inputStart"] == 480 and
                 frame["object"] == birth["object"] and len(returned) <= 1 and bool(trace))
        if returned:
            terminal = "HOST_RETURNED"
        elif trace and trace[-1]["status"] == 2:
            terminal = "PENDING"
        elif trace:
            terminal = "DISCARD"
        else:
            terminal = "INVALID"
            valid = False
        if birth and any(e["frameCount"] != birth["frameCount"] for e in trace + returned):
            valid = False
        if any(e["status"] not in ACTIONS or e["id"] not in states for e in trace):
            valid = False
        summary = summaries.get(frame["parent"]) if frame else None
        result.append({
            "source_key": list(key), "source_event_id": birth["id"] if birth else None,
            "clean48_interval": [0, birth["frameCount"]] if birth else None,
            "aec_call_id": frame["id"] if frame else None,
            "raw48_call_interval": [frame["inputStart"], frame["inputEnd"]] if frame else None,
            "aec_internal_epoch": "UNVERIFIED", "physical_source": "UNVERIFIED",
            "raw_to_clean_dsp_support": "DSP_SUPPORT_UNVERIFIED",
            "actions": [{"event_id": e["id"], "action": ACTIONS.get(e["status"], "UNKNOWN"),
                         "origin_gate_epoch": e["epoch"], "at": e["entered"],
                         "classification": e["format"], "gate_open": bool(e["flags"] & 2),
                         "current_gate_epoch": states.get(e["id"], {}).get("epoch"),
                         "reason": states.get(e["id"], {}).get("status"),
                         "context": states.get(e["id"], {}).get("detail")} for e in trace],
            "decision_events": [{"event_id": e["id"], "branch": e["status"], "classification": e["format"],
                                 "gate_open": bool(e["flags"] & 2), "gate_epoch": e["epoch"],
                                 "pre_roll_frames": e["remainderBefore"], "hangover_frames": e["remainderAfter"]}
                                for e in decisions[key]],
            "host_return_events": [e["id"] for e in returned],
            "returned_spans": [{"event_id": e["id"], "host_call_id": e["parent"],
                                "call_sample_interval": [e["outputStart"], e["outputEnd"]],
                                "gate_epoch": e["epoch"], "gate_open": bool(e["flags"] & 2),
                                "classification": e["format"]} for e in returned],
            "host_call_status": summary["status"] if summary else None,
            "active_zero": any(e["status"] == 4 for e in trace),
            "terminal": terminal if valid else "INVALID",
            "validity": "EXACT_LEDGER" if valid else "INVALID",
            "reason": None if valid else "SOURCE_MISSING_DUPLICATE_OR_UNPROVEN",
        })
    return result


def nominal_parents(output, interval, conversions, outputs, spans):
    rate = struct.unpack("<d", struct.pack("<Q", output["sampleRate"]))[0]
    if rate <= 0 or not rate < 1_000_000 or output["flags"] & 128:
        return [], "INVALID"
    ratio = Fraction(str(rate)) / 24000
    low, high = Fraction(interval[0]) * ratio, Fraction(interval[1]) * ratio
    parents, cursor = [], low
    for entry in sorted(conversions, key=lambda e: e["inputStart"]):
        if (entry["object"], entry["epoch"]) != (output["object"], output["epoch"]):
            continue
        if not entry["flags"] & 256:
            continue
        lo, hi = max(low, entry["inputStart"]), min(high, entry["inputEnd"])
        if lo >= hi:
            continue
        owner = one([s for s in spans if inside(entry, s)])
        host = one([e for e in outputs if owner and snapshot_key(e) == snapshot_key(owner)
                    and e["thread"] == owner["thread"] and e["completed"] <= owner["entered"]])
        parents.append({"conversion_event_id": entry["id"],
                        "submitted_input_interval": [str(lo), str(hi)],
                        "source_span_interval": [str(lo - entry["inputStart"]), str(hi - entry["inputStart"])],
                        "input_span_event_id": owner["id"] if owner else None,
                        "host_return_event_id": host["id"] if host else None,
                        "validity": "NOMINAL_RESAMPLE" if host else "INVALID",
                        "support": "DSP_SUPPORT_UNVERIFIED"})
        if lo != cursor:
            return parents, "INVALID"
        cursor = hi
    return parents, "NOMINAL_RESAMPLE" if cursor == high and parents and all(
        p["host_return_event_id"] is not None for p in parents) else "INVALID"


def packet_records(events):
    inputs = [e for e in events if e["kind"] == 15]
    conversions = [e for e in events if e["kind"] == 13]
    outputs = [e for e in events if e["kind"] == 12 and not e["flags"] & 8]
    spans = [e for e in events if e["kind"] == 22]
    deliveries = [e for e in events if e["kind"] == 20]
    packets = [e for e in events if e["kind"] == 16]
    buffer_entries = [e for e in events if e["kind"] == 19 and e["status"] in (6, 7)]
    terminals = defaultdict(list)
    for event in events:
        if event["kind"] == 19 and event["status"] in (8, 9, 10):
            terminals[event["object"], event["generation"], event["inputStart"]].append(event)
    results = []
    for packet in packets:
        cursor, fragments, valid = packet["inputStart"], [], True
        for entry in sorted(inputs, key=lambda e: e["inputStart"]):
            if (entry["object"], entry["epoch"]) != (packet["object"], packet["epoch"]):
                continue
            lo, hi = max(packet["inputStart"], entry["inputStart"]), min(packet["inputEnd"], entry["inputEnd"])
            if lo >= hi:
                continue
            transaction = one([e for e in conversions if inside(entry, e)])
            nominal, support = [], "INVALID"
            if transaction and transaction["status"] == 0:
                start = transaction["outputStart"] + lo - entry["inputStart"]
                nominal, support = nominal_parents(transaction, [start, start + hi - lo], conversions, outputs, spans)
            fragments.append({"packet_input_event_id": entry["id"], "float24_interval": [lo, hi],
                              "representative_frame": entry["reserved"], "representative_classification": entry["format"],
                              "representative_gate_open": bool(entry["flags"] & 2),
                              "conversion_event_id": transaction["id"] if transaction else None,
                              "nominal_parent_fragments": nominal, "upstream_validity": support})
            valid = valid and lo == cursor
            cursor = hi
        valid = (valid and cursor == packet["inputEnd"] and len(fragments) > 0 and
                 packet["inputEnd"] - packet["inputStart"] == packet["frameCount"] == 480 and
                 packet["outputEnd"] - packet["outputStart"] == 480)
        delivery = one([e for e in deliveries if inside(packet, e)])
        entry = None
        if delivery:
            siblings = sorted([e for e in packets if inside(e, delivery)], key=lambda e: e["id"])
            attempts = sorted([e for e in buffer_entries if inside(e, delivery)], key=lambda e: e["id"])
            if delivery["status"] == 0 and len(siblings) == len(attempts) == delivery["outputEnd"]:
                entry = attempts[siblings.index(packet)]
        state, terminal_ids = "PENDING", []
        if delivery and delivery["status"] != 0:
            state = "DISCARD_BATCH_FAILURE"
        elif entry:
            if entry["status"] == 7:
                state = "REJECTED"
            else:
                ends = terminals[entry["object"], entry["generation"], entry["inputStart"]]
                terminal_ids = [e["id"] for e in ends]
                state = {8: "DROP_OLDEST", 9: "DRAINED", 10: "CLEARED"}.get(ends[0]["status"], "INVALID") if len(ends) == 1 else "PENDING" if not ends else "INVALID"
        elif delivery:
            state = "INVALID"
        batches = [e for e in events if e["kind"] == 14 and inside(packet, e)]
        if len(batches) == 1 and batches[0]["status"] != 0:
            state = "DISCARD_BATCH_FAILURE"
        owner = one([e for e in inputs if e["id"] == packet["parent"]])
        siblings = sorted([e for e in packets if owner and e["parent"] == owner["id"]], key=lambda e: e["id"])
        encodings = sorted([e for e in events if e["kind"] == 17 and owner and inside(e, owner)], key=lambda e: e["id"])
        encoding = encodings[siblings.index(packet)] if len(encodings) == len(siblings) and siblings else None
        valid = valid and encoding is not None and encoding["frameCount"] == packet["frameCount"]
        zero_ranges = [{"reason": "NONFINITE" if e["status"] == 1 else "QUANTIZATION_ZERO",
                        "output24_interval": [packet["outputStart"] + e["inputStart"],
                                              packet["outputStart"] + e["inputEnd"]]}
                       for e in events if e["kind"] == 24 and encoding and e["parent"] == encoding["id"]]
        results.append({"packet_id": packet["id"], "encoding_event_id": encoding["id"] if encoding else None,
                        "zero_ranges": zero_ranges, "packetizer": packet["object"],
                        "epoch": packet["epoch"], "output24_interval": [packet["outputStart"], packet["outputEnd"]],
                        "ready_at": packet["completed"], "fragments": fragments,
                        "representative_snapshot": {k: packet[k] for k in ("reserved", "detail", "contentTime", "format", "flags")},
                        "sample_ledger": "EXACT_LEDGER" if valid else "INVALID",
                        "physical_source": "DSP_SUPPORT_UNVERIFIED", "terminal": state,
                        "buffer_event_id": entry["id"] if entry else None,
                        "generation": entry["generation"] if entry else None,
                        "buffer_terminal_events": terminal_ids})
    return results


def queue_records(events):
    entries = defaultdict(list)
    ends = defaultdict(list)
    rejected = []
    for event in events:
        if event["kind"] != 19:
            continue
        key = event["object"], event["generation"], event["inputStart"]
        if event["status"] == 6:
            entries[key].append(event)
        elif event["status"] == 7:
            rejected.append({"event_id": event["id"], "terminal": "REJECTED", "generation": event["generation"]})
        else:
            ends[key].append(event)
    result = []
    for key in sorted(set(entries) | set(ends)):
        admitted = one(entries[key])
        terminal = one(ends[key])
        valid = (admitted is not None and len(ends[key]) <= 1 and
                 (terminal is None or (terminal["frameCount"] == admitted["frameCount"] and
                                      terminal["entered"] >= admitted["began"])))
        result.append({"queue_key": list(key), "accepted_event_id": admitted["id"] if admitted else None,
                       "terminal_event_id": terminal["id"] if terminal else None,
                       "sample_count": admitted["frameCount"] if admitted else None,
                       "validity": "EXACT_LEDGER" if valid else "INVALID",
                       "terminal": {8: "DROP_OLDEST", 9: "DRAINED", 10: "CLEARED"}.get(
                           terminal["status"], "INVALID") if terminal and valid else "PENDING" if valid else "INVALID"})
    return result, rejected


def conversion_records(events):
    outputs = [e for e in events if e["kind"] == 12 and not e["flags"] & 8]
    spans = [e for e in events if e["kind"] == 22]
    claimed = defaultdict(list)
    result = []
    for event in (e for e in events if e["kind"] == 13):
        source = one([e for e in spans if inside(event, e)])
        returned = one([e for e in outputs if source and snapshot_key(e) == snapshot_key(source)
                        and e["thread"] == source["thread"] and e["completed"] <= source["entered"]])
        if returned and event["flags"] & 256:
            claimed[returned["id"]].append(event["id"])
        children = [e for e in events if e["kind"] == 15 and inside(e, event)]
        result.append({"event_id": event["id"], "converter": event["object"], "epoch": event["epoch"],
                       "host_return_event_id": returned["id"] if returned else None,
                       "input_submission": "SUPPLIED" if event["flags"] & 256 else "NOT_SUPPLIED",
                       "submitted_input_interval": [event["inputStart"], event["inputEnd"]],
                       "internal_consumption": "DSP_SUPPORT_UNVERIFIED",
                       "observed_float24_interval": [event["outputStart"], event["outputEnd"]],
                       "packetizer_inputs": [e["id"] for e in children],
                       "terminal": "PACKETIZER_SUBMITTED" if children and event["status"] == 0
                       else "INVALID_CONVERSION_OR_UNRETURNED_OUTPUT" if event["status"] != 0 else "PENDING"})
    duplicates = [{"host_return_event_id": key, "conversion_events": values}
                  for key, values in claimed.items() if len(values) > 1]
    return result, duplicates


def input_ownership(events, conversions):
    result = []
    for event in (e for e in events if e["kind"] == 12 and not e["flags"] & 8):
        children = [c for c in conversions if c["host_return_event_id"] == event["id"]
                    and c["input_submission"] == "SUPPLIED"]
        valid = len(children) == 1 and (children[0]["submitted_input_interval"][1] -
                                       children[0]["submitted_input_interval"][0] == event["frameCount"])
        result.append({"host_return_event_id": event["id"], "span_interval": [0, event["frameCount"]],
                       "conversion_events": [c["event_id"] for c in children],
                       "ownership": "SUBMITTED" if valid else "INVALID",
                       "reason": "INTERNAL_CONSUMPTION_UNVERIFIED" if valid
                       else "NO_UNIQUE_COMPLETE_SUBMISSION_UNPROCESSED_OR_UNOBSERVED"})
    return result


def reconcile(events, footer):
    gates = classify_gates(events)
    packets = packet_records(events)
    queues, rejected = queue_records(events)
    conversions, duplicate_sources = conversion_records(events)
    ownership = input_ownership(events, conversions)
    source_by_return = {event: gate for gate in gates for event in gate["host_return_events"]}
    for packet in packets:
        for fragment in packet["fragments"]:
            for parent in fragment["nominal_parent_fragments"]:
                source = source_by_return.get(parent["host_return_event_id"])
                parent["clean_source_event_id"] = source["source_event_id"] if source else None
                parent["gate_source_validity"] = source["validity"] if source else "INVALID"
    pending = []
    discards = []
    for event in events:
        if event["kind"] == 18 and event["status"] in (1, 4) and event["remainderBefore"]:
            discards.append({"event_id": event["id"], "object": event["object"], "epoch": event["epoch"],
                             "float24_interval": [event["outputEnd"], event["inputEnd"]],
                             "terminal": "DISCARD", "reason": "RESET" if event["status"] == 1 else "DEINIT"})
        if event["kind"] == 15 and event["remainderAfter"]:
            later = [e for e in events if e["object"] == event["object"] and e["id"] > event["id"]
                     and e["kind"] in (15, 18)]
            if not later:
                pending.append({"object": event["object"], "epoch": event["epoch"],
                                "float24_interval": [event["outputEnd"], event["inputEnd"]], "terminal": "PENDING"})
    duplicate_ids = len({e["id"] for e in events}) != len(events)
    recorder_valid = not any(footer[k] for k in ("flags", "detail", "remainderAfter")) and not duplicate_ids
    invalid = bool(duplicate_sources) or any(g["validity"] == "INVALID" for g in gates) or any(q["validity"] == "INVALID" for q in queues)
    invalid = invalid or any(c["input_submission"] == "SUPPLIED" and c["host_return_event_id"] is None
                            for c in conversions)
    invalid = invalid or any(s["ownership"] == "INVALID" for s in ownership)
    host_returns = [e for e in events if e["kind"] == 12 and not e["flags"] & 8]
    for summary in (e for e in events if e["kind"] == 12 and e["flags"] & 8):
        returned = sorted([e for e in host_returns if e["parent"] == summary["parent"]],
                          key=lambda e: e["outputStart"])
        cursor = 0
        for entry in returned:
            invalid = invalid or entry["outputStart"] != cursor
            invalid = invalid or entry["outputEnd"] - entry["outputStart"] != entry["frameCount"]
            cursor = entry["outputEnd"]
        invalid = invalid or len(returned) != summary["frameCount"]
    invalid = invalid or any(p["sample_ledger"] == "INVALID" or p["terminal"] == "INVALID" or
                            any(f["upstream_validity"] == "INVALID" for f in p["fragments"]) for p in packets)
    if not recorder_valid:
        for gate in gates:
            gate["validity"] = "INVALID"
        for packet in packets:
            packet["sample_ledger"] = "INVALID"
            for fragment in packet["fragments"]:
                fragment["upstream_validity"] = "INVALID"
                for parent in fragment["nominal_parent_fragments"]:
                    parent["validity"] = parent["gate_source_validity"] = "INVALID"
        for queue in queues:
            queue["validity"] = "INVALID"
        for source in ownership:
            source["ownership"] = "INVALID"
            source["reason"] = "RECORDER_INCOMPLETE"
    return {"schema_version": 1, "recorder_valid": recorder_valid,
            "acceptance": "REQUIRES_CONTROL_SEAL_SUMMARY", "gate_sources": gates, "packets": packets,
            "queue_entries": queues, "queue_rejections": rejected,
            "conversions": conversions, "duplicate_source_submissions": duplicate_sources,
            "host_input_ownership": ownership,
            "pending_packetizer_ranges": pending, "discarded_packetizer_ranges": discards,
            "conversion_events": [e for e in events if e["kind"] in (13, 14, 18, 22)],
            "encoding_events": [e for e in events if e["kind"] in (17, 24)],
            "control_events": [e for e in events if e["kind"] in (21, 23)],
            "validity": "INVALID" if not recorder_valid or invalid else "NOMINAL_RESAMPLE" if packets else "EXACT_LEDGER",
            "dsp_support": "DSP_SUPPORT_UNVERIFIED", "physical_human_source": "UNVERIFIED"}


def inspect(path):
    envelope = SCALAR.inspect(path)  # Preserve the frozen envelope/integrity acceptance rules.
    data = Path(path).read_bytes()
    records = [dict(zip(SCALAR.FIELDS, SCALAR.RECORD.unpack_from(data, offset)))
               for offset in range(0, len(data), SCALAR.RECORD.size)]
    result = reconcile(records[1:-1], records[-1])
    result["run_id"] = envelope["run_id"]
    result["recorder_integrity"] = {k: envelope[k] for k in ("validity", "invalid_reasons", "written", "lost", "pending")}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact")
    args = parser.parse_args()
    print(json.dumps(inspect(args.artifact), separators=(",", ":")))
