#!/usr/bin/env python3
"""Offline identity audit of one ProbeTransport wire.ndjson per connection.

No Provider calls, transcript output, or production decisions. Exit codes:
0 = complete, identity-consistent evidence; 1 = identity anomaly;
2 = invalid/incomplete evidence. --self-test validates the checker, not Qwen.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import unittest


FINAL = "conversation.item.input_audio_transcription.completed"
ADDED = "response.output_item.added"
ITEM_DONE = "response.output_item.done"
DONE = "response.done"
END_TYPES = {"response.audio_transcript.done", "response.text.done", "response.audio.done"}


def alias(value):
    if not isinstance(value, str) or not re.fullmatch(r"id_[1-9][0-9]*", value):
        raise ValueError("expected a ProbeTransport ID alias")
    return value


def decode(data):
    events = []
    previous_time = -1
    for line_number, line in enumerate(data.splitlines(), 1):
        try:
            record = json.loads(line)
            sequence = record["sequence"]
            timestamp = record["elapsedNanoseconds"]
            event = json.loads(record["replayFrame"])
            if (type(sequence) is not int or sequence != line_number
                    or type(timestamp) is not int or timestamp < 0 or timestamp < previous_time
                    or not isinstance(event, dict) or not isinstance(event.get("type"), str)):
                raise ValueError("sequence, clock, or event shape invalid")
        except (ValueError, TypeError, KeyError) as error:
            raise ValueError("invalid record at line %d" % line_number) from error
        previous_time = timestamp
        events.append((sequence, timestamp, event))
    if not events or events[0][2]["type"] != "session.created":
        raise ValueError("capture must begin with session.created")
    if sum(event["type"] == "session.created" for _, _, event in events) != 1:
        raise ValueError("use one connection per input file")
    return events


def collect(events):
    responses, users, evidence = {}, {}, {}
    for sequence, timestamp, event in events:
        kind = event["type"]
        identity = {"sequence": sequence, "elapsed_ns": timestamp, "type": kind}
        user_field = None
        if kind == "input_audio_buffer.speech_started":
            user_field = "speech_start"
        elif kind == FINAL:
            user_field = "transcript_final"
        elif kind == "conversation.item.created":
            item = event["item"]
            if any(part.get("type") == "input_audio" for part in item.get("content", [])):
                user_field = "input_item_created"
        if user_field:
            item_id = alias(event["item"]["id"] if kind == "conversation.item.created"
                            else event["item_id"])
            users.setdefault(item_id, {}).setdefault(user_field, sequence)
            identity["item_id"] = item_id
            evidence[sequence] = identity
            continue
        if kind == "response.created":
            response_id = alias(event["response"]["id"])
            responses.setdefault(response_id, {"created": sequence, "added": {}, "ends": [],
                                                "done": None})
            identity["response_id"] = response_id
        elif kind in {ADDED, ITEM_DONE, DONE} | END_TYPES:
            response_id = alias(event["response"]["id"] if kind == DONE else event["response_id"])
            if response_id not in responses:
                raise ValueError("output without response.created at sequence %d" % sequence)
            response = responses[response_id]
            identity["response_id"] = response_id
            if kind == DONE:
                items = event["response"]["output"]
                if not isinstance(items, list):
                    raise ValueError("response output must be an array")
                item_ids = [alias(item["id"]) for item in items]
                response["done"] = response["done"] or sequence
            else:
                item_ids = [alias(event["item"]["id"] if kind in {ADDED, ITEM_DONE}
                                  else event["item_id"])]
            identity["item_ids"] = item_ids
            if kind == ADDED:
                response["added"].setdefault(item_ids[0], sequence)
            else:
                response["ends"].append((sequence, item_ids))
        else:
            continue
        evidence[sequence] = identity
    return responses, users, evidence


def analyze(data):
    events = decode(data)
    try:
        responses, users, evidence = collect(events)
    except (KeyError, TypeError, AttributeError) as error:
        raise ValueError("invalid identity event fields") from error
    rows = []
    for ordinal, (response_id, response) in enumerate(responses.items(), 1):
        mismatches, collisions, selected = [], [], {response["created"]}
        selected.update(response["added"].values())
        for sequence, item_ids in response["ends"]:
            selected.add(sequence)
            for item_id in item_ids:
                if item_id not in response["added"] or response["added"][item_id] > sequence:
                    mismatches.append({"sequence": sequence, "item_id": item_id})
                user = users.get(item_id)
                if user:
                    selected.update(user.values())
                    final = user.get("transcript_final")
                    relation = ("final_before_output" if final and final < sequence else
                                "final_after_output" if final else "speech_or_input_only")
                    collisions.append({"sequence": sequence, "item_id": item_id,
                                       "relation": relation, **user})
        terminal = response["done"]
        terminal_items = next((ids for seq, ids in response["ends"] if seq == terminal), [])
        incomplete = (not terminal or not response["added"]
                      or not terminal_items)
        rows.append({
            "response_ordinal": ordinal, "response_id": response_id,
            "created_sequence": response["created"], "done_sequence": terminal,
            "added_item_ids": list(response["added"]), "done_item_ids": terminal_items,
            "incomplete": bool(incomplete), "identity_changes": mismatches,
            "user_item_collisions": collisions,
            "evidence": [evidence[seq] for seq in sorted(selected)],
        })
    counts = {
        "responses": len(rows),
        "complete_responses": sum(not row["incomplete"] for row in rows),
        "identity_changed_responses": sum(bool(row["identity_changes"]) for row in rows),
        "final_user_collision_responses": sum(any(
            hit["relation"] == "final_before_output" for hit in row["user_item_collisions"])
            for row in rows),
        "consistent_responses": sum(not row["incomplete"] and not row["identity_changes"]
                                    and not row["user_item_collisions"] for row in rows),
    }
    anomaly = any(row["identity_changes"] or row["user_item_collisions"] for row in rows)
    incomplete = not rows or any(row["incomplete"] for row in rows)
    return {"schema_version": 1, "wire_sha256": hashlib.sha256(data).hexdigest(),
            "records": len(events), "counts": counts, "responses": rows,
            "status": "INCONCLUSIVE" if incomplete else
                      "IDENTITY_ANOMALY" if anomaly else "IDENTITY_CONSISTENT",
            "semantic_causality": "NOT_PROVEN", "production_adapter_executed": False}


def markdown(reports):
    lines = ["# 离线消息身份检查", "",
             "仅分析已保存的入站事件；未调用 Provider，未执行生产 Adapter。",
             "身份异常不等于已证明服务端覆盖上下文，也不等于修复语义问题。", ""]
    for number, report in enumerate(reports, 1):
        lines += ["## 样本 %d：%s" % (number, report["status"]), "",
                  "wire SHA256：`%s`" % report["wire_sha256"], "",
                  "| 回答序号 | response | 开始 item | 完成 item | ID 变化 | 与已 final 用户重合 | 完整 |",
                  "|---|---|---|---|---|---|---|"]
        for row in report["responses"]:
            collision = any(hit["relation"] == "final_before_output"
                            for hit in row["user_item_collisions"])
            lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (
                row["response_ordinal"], row["response_id"], ", ".join(row["added_item_ids"]),
                ", ".join(row["done_item_ids"]), bool(row["identity_changes"]),
                collision, not row["incomplete"]))
        lines += ["", "计数：`%s`" % json.dumps(report["counts"], sort_keys=True), ""]
    return "\n".join(lines) + "\n"


def fixture(completion_id="id_2", user_final=False, late_final=False):
    events = [{"type": "session.created"},
              {"type": "response.created", "response": {"id": "id_1"}},
              {"type": ADDED, "response_id": "id_1", "item": {"id": "id_2"}}]
    if user_final or late_final:
        events.append({"type": "input_audio_buffer.speech_started", "item_id": "id_3"})
    if user_final:
        events.append({"type": FINAL, "item_id": "id_3"})
    events.append({"type": DONE, "response": {"id": "id_1", "output": [{"id": completion_id}]}})
    if late_final:
        events.append({"type": FINAL, "item_id": "id_3"})
    return events


def encoded(events):
    return "\n".join(json.dumps({"sequence": i, "elapsedNanoseconds": i * 1000,
                                "replayFrame": json.dumps(event)})
                     for i, event in enumerate(events, 1)).encode()


class IdentityTests(unittest.TestCase):
    def test_normal_no_overlap(self):
        self.assertEqual(analyze(encoded(fixture()))["status"], "IDENTITY_CONSISTENT")

    def test_overlap_distinct_ids(self):
        self.assertEqual(analyze(encoded(fixture(user_final=True)))["status"], "IDENTITY_CONSISTENT")

    def test_final_before_old_done(self):
        report = analyze(encoded(fixture("id_3", user_final=True)))
        self.assertEqual(report["counts"]["final_user_collision_responses"], 1)
        self.assertEqual(report["counts"]["identity_changed_responses"], 1)
        self.assertEqual(report["status"], "IDENTITY_ANOMALY")

    def test_final_after_old_done_is_separate(self):
        report = analyze(encoded(fixture("id_3", late_final=True)))
        self.assertEqual(report["counts"]["final_user_collision_responses"], 0)
        self.assertEqual(report["responses"][0]["user_item_collisions"][0]["relation"],
                         "final_after_output")

    def test_provisional_id_does_not_imply_final_collision(self):
        events = fixture("id_3", late_final=True)
        events[-1]["item_id"] = "id_4"
        report = analyze(encoded(events))
        self.assertEqual(report["counts"]["final_user_collision_responses"], 0)
        self.assertEqual(report["responses"][0]["user_item_collisions"][0]["relation"],
                         "speech_or_input_only")

    def test_change_without_user_is_still_detected(self):
        report = analyze(encoded(fixture("id_4")))
        self.assertEqual(report["counts"]["identity_changed_responses"], 1)
        self.assertEqual(report["counts"]["final_user_collision_responses"], 0)

    def test_intermediate_end_cannot_be_hidden_by_correct_response_done(self):
        for kind in END_TYPES | {ITEM_DONE}:
            with self.subTest(kind=kind):
                events = fixture(user_final=True)
                event = {"type": kind, "response_id": "id_1"}
                event.update({"item": {"id": "id_3"}} if kind == ITEM_DONE
                             else {"item_id": "id_3"})
                events.insert(-1, event)
                report = analyze(encoded(events))
                self.assertEqual(report["counts"]["final_user_collision_responses"], 1)
                self.assertEqual(report["status"], "IDENTITY_ANOMALY")

    def test_duplicate_done_does_not_inflate_response_count(self):
        events = fixture("id_3", user_final=True)
        events.append(events[-1])
        report = analyze(encoded(events))
        self.assertEqual(report["counts"]["responses"], 1)
        self.assertEqual(report["counts"]["final_user_collision_responses"], 1)

    def test_multiple_output_items_are_not_a_false_collision(self):
        events = fixture()
        events.insert(-1, {"type": ADDED, "response_id": "id_1", "item": {"id": "id_4"}})
        events[-1]["response"]["output"].append({"id": "id_4"})
        self.assertEqual(analyze(encoded(events))["status"], "IDENTITY_CONSISTENT")

    def test_incomplete_capture_cannot_pass(self):
        self.assertEqual(analyze(encoded(fixture()[:-1]))["status"], "INCONCLUSIVE")
        self.assertEqual(analyze(encoded(fixture()[:1]))["status"], "INCONCLUSIVE")

    def test_repeated_runs_do_not_share_alias_state(self):
        analyze(encoded(fixture("id_3", user_final=True)))
        data = encoded(fixture())
        self.assertEqual(analyze(data), analyze(data))
        self.assertEqual(analyze(data)["status"], "IDENTITY_CONSISTENT")

    def test_invalid_evidence_fails_closed(self):
        data = encoded(fixture())
        for invalid in (b"", b"{", data.replace(b'"sequence": 2', b'"sequence": 8'),
                        data.replace(b'"elapsedNanoseconds": 1000', b'"elapsedNanoseconds": -1'),
                        data.replace(b'"elapsedNanoseconds": 2000', b'"elapsedNanoseconds": -1'),
                        data.replace(b"id_2", b"unsanitized-id"),
                        encoded(fixture() + [{"type": "session.created"}])):
            with self.subTest(invalid=invalid[:20]), self.assertRaises(ValueError):
                analyze(invalid)

    def test_report_does_not_copy_text(self):
        events = fixture("id_3", user_final=True)
        events[-2]["transcript"] = "private-sentinel"
        report = analyze(encoded(events))
        self.assertNotIn("private-sentinel", json.dumps(report))
        self.assertNotIn("private-sentinel", markdown([report]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wire", type=Path, nargs="*")
    parser.add_argument("--output-dir", type=Path, help="existing directory; never overwrite reports")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(
            unittest.defaultTestLoader.loadTestsFromTestCase(IdentityTests))
        return 0 if result.wasSuccessful() else 1
    if not args.wire or not args.output_dir:
        parser.error("wire paths and --output-dir are required")
    try:
        reports = [analyze(path.read_bytes()) for path in args.wire]
        output = {"schema_version": 1, "checker_sha256": hashlib.sha256(
            Path(__file__).read_bytes()).hexdigest(), "samples": reports}
        for name, contents in (("identity-report.json", json.dumps(output, indent=2) + "\n"),
                               ("identity-report.md", markdown(reports))):
            with (args.output_dir / name).open("x", encoding="utf-8") as destination:
                destination.write(contents)
    except (OSError, ValueError) as error:
        # Do not echo malformed payloads or user-local input paths.
        print("INVALID_EVIDENCE_OR_OUTPUT: " + type(error).__name__, file=sys.stderr)
        return 2
    for number, report in enumerate(reports, 1):
        print(json.dumps({"sample": number, "status": report["status"], **report["counts"]}))
    if any(report["status"] == "INCONCLUSIVE" for report in reports):
        return 2
    return 1 if any(report["status"] == "IDENTITY_ANOMALY" for report in reports) else 0


if __name__ == "__main__":
    sys.exit(main())
