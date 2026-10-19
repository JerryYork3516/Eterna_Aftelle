"""REF event translation using the frozen SingleRun; no player or execution entrypoint."""
import ast
import hashlib
import json
from pathlib import Path
import uuid

CONTROLLER_SHA = "b81621be6448803ddb3b2c4c7bdaf57fd6cb673ec1898c525758896574692cd9"


def original_single_run(path):
    source = Path(path).read_bytes()
    if hashlib.sha256(source).hexdigest() != CONTROLLER_SHA:
        raise ValueError("original controller identity mismatch")
    tree = ast.parse(source)
    definition = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "SingleRun")
    namespace = {"uuid": uuid}
    exec(compile(ast.Module(body=[definition], type_ignores=[]), str(path), "exec"), namespace)
    return namespace["SingleRun"]


def schedule(raw):
    if len(json.dumps(raw, separators=(",", ":")).encode())+1 > 512:
        raise ValueError("oversized event")
    if (raw["schema_version"], raw["source"], raw["clock"], raw["event"]) != (
            1, "ADAPTED_REF", "mach_absolute_nanoseconds", "schedule"):
        raise ValueError("invalid REF schedule identity")
    uuid.UUID(raw["run_id"])
    a = raw["anchor"]
    for value in a.values():
        if type(value) is not int or not 0 <= value <= 2**64-1:
            raise ValueError("invalid clock integer")
    if not (0 < a["numer"] < 2**32 and 0 < a["denom"] < 2**32 and a["continuous"] > 0):
        raise ValueError("invalid timebase")
    before = a["absolute_before"] * a["numer"] // a["denom"]
    after = a["absolute_after"] * a["numer"] // a["denom"]
    if not 0 <= after-before <= 1_000_000 or after > 2**64-1-9_000_000_000:
        raise ValueError("invalid clock bracket")
    start = before + (after-before)//2
    if (raw["observation_start_ns"], raw["near_start_ns"], raw["near_stop_ns"]) != (
            start, start+4_000_000_000, start+9_000_000_000):
        raise ValueError("clock mapping/near window mismatch")
    return dict(schema_version=1, clock=raw["clock"], event="schedule", run_id=raw["run_id"],
                score_start_ns=raw["near_start_ns"], proxy_stop_ns=raw["near_start_ns"]+11_000_000_000)


class ReferenceRun:
    def __init__(self, original):
        self.plan = original(4)

    def accept(self, raw, now):
        if raw["event"] == "schedule":
            self.plan.accept(schedule(raw), now)
            # Only this registered REF window is five seconds; the HOST class is untouched.
            self.plan.stop = raw["near_stop_ns"]
        elif raw["event"] in ("cancel", "stop"):
            if (raw["schema_version"], raw["source"], raw["clock"]) != (
                    1, "ADAPTED_REF", "mach_absolute_nanoseconds"):
                raise ValueError("invalid REF terminal identity")
            self.plan.accept(dict(schema_version=1, clock=raw["clock"], event="stop", run_id=raw["run_id"]), now)
        else:
            raise ValueError("unknown REF event")

    def actions(self, now):
        return self.plan.actions(now)
