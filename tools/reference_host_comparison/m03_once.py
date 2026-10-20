"""R5-M03: reuse the HOST control loop for one explicitly authorized source group."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess

from integration import (
    PLAYER_BINARY_SHA, _connected_run, command, disabled_spawn, now_ns,
    require_identity, verify_bundle,
)

CONSENT = "R5_M03_ABC_ONCE_LOCAL_RECORDING_AND_ANALYSIS"


def run(bundle, group, executable, evidence, *, consent=None, spawn=disabled_spawn, clock=now_ns):
    if group not in ("A", "B", "C"):
        raise ValueError("unregistered group")
    device = consent == CONSENT
    if not device and not getattr(spawn, "device_disabled", False):
        disabled_spawn()
    bundle, _ = verify_bundle(bundle, "REF")  # Original nonzero-start proxy, never HOST_proxy.
    require_identity(bundle / "bt_proxy_registered", PLAYER_BINARY_SHA)
    command("HOST", executable, 3, m03_group=group)
    evidence = Path(evidence).absolute()
    parent = evidence.parent
    if evidence.resolve() != evidence or parent.stat().st_uid != os.getuid() or parent.stat().st_mode & 0o777 != 0o700:
        raise ValueError("owned 0700 evidence directory required")
    if group != "A":
        previous = parent / ("A" if group == "B" else "B")
        result = json.loads((previous / "result.json").read_text())
        release = json.loads((previous / "release.json").read_text())
        expected = "CONTROL_COMPLETED_DEVICE" if device else "PASS_OFFLINE_CONTROL_ONLY"
        if result["status"] != expected or release.get("safe_to_continue") is not True:
            raise ValueError("previous group has not safely sealed/exported/released")
    fd = os.open(parent / ("M03_" + group + "_consumed.json"),
                 os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(dict(schema_version=1, group=group, consent=consent,
                       status="ATTEMPT_RESERVED", device=device), output)

    def cancelled(signum, frame):
        raise InterruptedError("M03 operator cancellation")

    previous_handler = signal.signal(signal.SIGTERM, cancelled)
    try:
        return _connected_run(bundle, "HOST", executable, evidence,
                              spawn=subprocess.Popen if device else spawn, clock=clock,
                              device=device, m03_group=group)
    finally:
        signal.signal(signal.SIGTERM, previous_handler)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=("A", "B", "C"), required=True)
    parser.add_argument("--consent", choices=(CONSENT,), required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    run(args.bundle, args.group, args.executable, args.evidence, consent=args.consent)
