"""One authorized human A/B/C run using the existing HOST lifecycle; no proxy process."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess

from integration import _connected_run, command, disabled_spawn, now_ns, verify_bundle

CONSENT = "R5_M07_HUMAN_ABC_ONCE_LOCAL_RECORDING_AND_ANALYSIS"
F1_CONSENT = "R5_M07_F1_HUMAN_AB_ONCE_LOCAL_RECORDING_AND_ANALYSIS"


def run(bundle, group, executable, evidence, *, consent=None, spawn=disabled_spawn, clock=now_ns, onset=False):
    if group not in (("A", "B") if onset else ("A", "B", "C")):
        raise ValueError("unregistered human group")
    batch = "R5_M07_F1" if onset else "R5_M07"
    device = consent == (F1_CONSENT if onset else CONSENT)
    if not device and not getattr(spawn, "device_disabled", False):
        disabled_spawn()
    bundle, _ = verify_bundle(bundle, "REF")  # Reuse registered controller only; no proxy launch.
    command("HOST", executable, 3, human_group="C" if onset else group, onset_group=group if onset else None)
    evidence = Path(evidence).absolute()
    parent = evidence.parent
    if evidence.resolve() != evidence or parent.stat().st_uid != os.getuid() or parent.stat().st_mode & 0o777 != 0o700:
        raise ValueError("owned 0700 evidence directory required")
    if group != "A":
        previous_group = "A" if group == "B" else "B"
        previous = parent / previous_group
        result = json.loads((previous / "result.json").read_text())
        release = json.loads((previous / "release.json").read_text())
        expected = "CONTROL_COMPLETED_DEVICE" if device else "PASS_OFFLINE_CONTROL_ONLY"
        if result["status"] != expected or release.get("safe_to_continue") is not True:
            raise ValueError("previous human group has not safely sealed/exported/released")
        if (result.get("batch"), result.get("group"), result.get("source")) != (batch, previous_group, "human") \
                or result.get("proxy_requested") is not False or not result.get("run_id") \
                or (release.get("batch"), release.get("group"), release.get("run_id")) != (batch, previous_group, result["run_id"]):
            raise ValueError("previous human run identity or release mismatch")
    fd = os.open(parent / (("M07_F1_" if onset else "M07_") + group + "_consumed.json"),
                 os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(dict(schema_version=1, batch=batch, group=group, consent=consent,
                       source="human", proxy_requested=False, status="ATTEMPT_RESERVED", device=device), output)

    def cancelled(signum, frame):
        raise InterruptedError("M07 operator cancellation")

    previous_handler = signal.signal(signal.SIGTERM, cancelled)
    try:
        return _connected_run(bundle, "HOST", executable, evidence,
                              spawn=subprocess.Popen if device else spawn, clock=clock,
                              device=device, human_group="C" if onset else group,
                              onset_group=group if onset else None)
    finally:
        signal.signal(signal.SIGTERM, previous_handler)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=("A", "B", "C"), required=True)
    parser.add_argument("--onset", action="store_true", help="F1 A/B only; separate current consent required")
    parser.add_argument("--consent", choices=(CONSENT, F1_CONSENT), required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    run(args.bundle, args.group, args.executable, args.evidence, consent=args.consent, onset=args.onset)
