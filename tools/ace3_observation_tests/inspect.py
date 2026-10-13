#!/usr/bin/env python3
"""Read only Step 2A scalar artifacts. Never decodes audio or invents timestamps."""
import argparse
import json
import struct

FIELDS = "id kind stream parent thread entered began completed contentTime nativeHostTime nativeSampleTime flags object epoch generation inputStart inputEnd outputStart outputEnd sampleRate format frameCount remainderBefore remainderAfter status detail run reserved".split()
RECORD = struct.Struct("<28Q")


def inspect(path):
    records = []
    with open(path, "rb") as source:
        while chunk := source.read(RECORD.size):
            if len(chunk) != RECORD.size:
                raise ValueError("INVALID: truncated scalar record")
            records.append(dict(zip(FIELDS, RECORD.unpack(chunk))))
    if not records or records[0]["kind"] != 100 or records[0]["id"] != 1:
        raise ValueError("INVALID: missing arm/schema")
    if records[-1]["kind"] != 101:
        raise ValueError("INVALID: missing seal (including process termination/write failure)")
    header, footer = records[0], records[-1]
    events = records[1:-1]
    if any(e["run"] != header["run"] for e in records):
        raise ValueError("INVALID: mixed run")
    if len({e["id"] for e in events}) != len(events):
        raise ValueError("INVALID: duplicate ticket")
    if len(events) != footer["outputStart"]:
        raise ValueError("INVALID: persisted event count mismatch")
    if footer["inputStart"] != footer["outputStart"] + footer["detail"] + footer["remainderAfter"]:
        raise ValueError("INVALID: reserved/written/lost/pending mismatch")
    native = [e for e in events if e["kind"] == 1]
    calls = {e["id"]: e for e in events if e["kind"] == 3}
    ancestors = {}
    conversions = {}
    for call in calls.values():
        roots = [e for e in native if e["thread"] == call["thread"]
                 and e["entered"] <= call["entered"] <= call["completed"] <= e["completed"]]
        ancestors[call["id"]] = roots[0] if len(roots) == 1 else None
        root = ancestors[call["id"]]
        candidates = [e for e in events if root and e["kind"] == 2
                      and e["thread"] == root["thread"]
                      and root["entered"] <= e["entered"] <= e["completed"] <= call["entered"]
                      and e["outputEnd"] - e["outputStart"] == call["inputEnd"] - call["inputStart"]]
        conversions[call["id"]] = candidates[0] if len(candidates) == 1 else None
    frame_sources = []
    for frame in (e for e in events if e["kind"] == 4):
        parent = calls.get(frame["parent"])
        root = ancestors.get(frame["parent"])
        fragments = []
        if parent and not frame["flags"] & 16:
            for call in calls.values():
                if (call["object"], call["epoch"], call["stream"]) != (frame["object"], frame["epoch"], frame["stream"]):
                    continue
                lo, hi = max(frame["inputStart"], call["inputStart"]), min(frame["inputEnd"], call["inputEnd"])
                if lo < hi:
                    origin = ancestors[call["id"]]
                    converter = conversions[call["id"]]
                    fragments.append({"host_call_id": call["id"], "callback_id": origin["id"] if origin else None,
                                      "converter_event_id": converter["id"] if converter else None,
                                      "converter_object": converter["object"] if converter else None,
                                      "converter_epoch": converter["epoch"] if converter else None,
                                      "converter_output_interval": [converter["outputStart"] + lo - call["inputStart"],
                                                                    converter["outputStart"] + hi - call["inputStart"]] if converter else None,
                                      "capture_generation": origin["generation"] if origin and not origin["flags"] & 8 else None,
                                      "raw48_interval": [lo, hi]})
        fragments.sort(key=lambda fragment: fragment["raw48_interval"])
        cursor, complete = frame["inputStart"], bool(fragments)
        for fragment in fragments:
            lo, hi = fragment["raw48_interval"]
            complete = complete and lo == cursor and fragment["callback_id"] is not None and fragment["converter_event_id"] is not None
            cursor = hi
        complete = complete and cursor == frame["inputEnd"]
        frame_sources.append({"frame_event_id": frame["id"], "execution_callback_id": root["id"] if root else None,
                              "source_fragments": fragments, "source_validity": "EXACT_CALL_LEDGER" if complete else "INVALID_OR_UNAVAILABLE"})
    return {"schema_version": 1, "run_id": f'{header["object"]:016x}{header["epoch"]:016x}',
            "validity": "INVALID" if footer["flags"] else "RECORDER_COMPLETE",
            "acceptance": "REQUIRES_CONTROL_SEAL_SUMMARY",
            "invalid_reasons": footer["flags"], "written": footer["outputStart"],
            "lost": footer["detail"], "pending": footer["remainderAfter"],
            "native_callbacks": len(native), "host_calls": len(calls), "aec_frames": len(frame_sources),
            "frame_sources": frame_sources}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact")
    args = parser.parse_args()
    print(json.dumps(inspect(args.artifact), separators=(",", ":")))
