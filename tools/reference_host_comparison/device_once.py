"""R4 explicit one-run launcher. Original application consent remains required."""
import argparse
from pathlib import Path

from integration import R4_CONSENT, run_device_once


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--authorize-device-once", choices=("REF", "HOST"), required=True)
    parser.add_argument("--consent", choices=(R4_CONSENT,), required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("ref_arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    original = args.ref_arguments
    if original[:1] == ["--"]:
        original = original[1:]
    run_device_once(args.bundle, args.authorize_device_once, args.executable,
                    args.evidence, original, consent=args.consent)


if __name__ == "__main__":
    main()
