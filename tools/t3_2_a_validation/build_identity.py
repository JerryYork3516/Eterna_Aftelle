"""Read build products and symbols without launching an application."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys


def inspect(derived):
    products = derived / "Build/Products"
    paths = {"debug_app": products / "Debug/Aftelle.app/Contents/MacOS/Aftelle",
             "debug_dylib": products / "Debug/Aftelle.app/Contents/MacOS/Aftelle.debug.dylib",
             "release_app": products / "Release/Aftelle.app/Contents/MacOS/Aftelle"}
    symbols = {}
    for name in ("debug_dylib", "release_app"):
        symbols[name] = subprocess.check_output(["nm", "-j", str(paths[name])],
                                                stderr=subprocess.DEVNULL).decode()
    witnesses = ("MacSpeechNativeVoiceTiming", "MacSpeechTimingSnapshot",
                 "MacSpeechPlaybackFormatWitness", "MacSpeechAppleVPDebugProfile",
                 "MacSpeechWarmupProfile", "MacSpeechAcousticWindowStats", "AppleVPWarmupDrainState")
    if not all(s in symbols["debug_dylib"] for s in witnesses):
        raise ValueError("DEBUG timing symbols missing")
    if any(s in symbols["release_app"] for s in witnesses):
        raise ValueError("DEBUG timing symbols leaked into Release")
    return {"sha256": {name: hashlib.sha256(p.read_bytes()).hexdigest()
                       for name, p in paths.items()},
            "debug_timing_symbols": "PRESENT", "release_timing_symbols": "ABSENT",
            "application_launched": False}


if __name__ == "__main__":
    print(json.dumps(inspect(Path(sys.argv[1])), sort_keys=True))
    print("build_identity_cases=1")
