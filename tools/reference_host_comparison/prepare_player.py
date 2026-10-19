"""Build a derived player from byte-verified local originals; never run it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
ORIGINAL_SOURCE_SHA = "e1340f6a26f0b1506f81d594c258b0520264bcecf4983356e3c70b5ba338a42c"
DEPENDENCY_SHA = "ac40e554ff1b414a758bbb4a4949406e01b2eed6b753a4c1f3db816516146423"
ORIGINAL_BINARY_SHA = "3f21479468417218617be4a122a417e865060a46d585b6614aa51a2537653b82"
CONTROLLER_SHA = "b81621be6448803ddb3b2c4c7bdaf57fd6cb673ec1898c525758896574692cd9"
FIXTURES = {
    "REF_proxy.wav": "1c7081f8271251804e01234be8a0ff8344062d09c311592634cb8fdf6b992d0a",
    "HOST_proxy.wav": "4a0b85b6fa3d14f14510d3f041ff1c41ee9b0363962c28dca812ce0ae83a55e8",
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require_identity(path, expected):
    if sha(path) != expected:
        raise ValueError("Frozen source/asset identity mismatch: " + Path(path).name)


def prepare(source, assets, output):
    source, assets, output = map(lambda p: Path(p).resolve(), (source, assets, output))
    if not output.is_relative_to(HERE.parents[1] / ".build"):
        raise ValueError("Output must be a new Git-ignored .build directory")
    dependency = Path(source.read_text().splitlines()[1].split('"')[1])
    originals = {source: ORIGINAL_SOURCE_SHA, dependency: DEPENDENCY_SHA,
                 source.with_suffix(""): ORIGINAL_BINARY_SHA, source.parent / "sync_once.py": CONTROLLER_SHA}
    for path, expected in originals.items():
        require_identity(path, expected)
    for name, expected in FIXTURES.items():
        require_identity(assets / name, expected)
    os.umask(0o077)
    output.mkdir(parents=True, exist_ok=False)
    receipt = {"schema_version": 1, "device_execution": "DISABLED", "commands": [], "files": {}}

    def run(name, command, cwd=None):
        start = time.monotonic()
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=120)
        log = output / (name + ".log")
        log.write_text(result.stdout + result.stderr)
        receipt["commands"].append(dict(name=name, command=list(map(str, command)), exit=result.returncode,
                                        seconds=time.monotonic() - start, log_sha256=sha(log)))
        (output / "build.json").write_text(json.dumps(receipt, indent=2))
        if result.returncode:
            raise RuntimeError(name + " failed; original exit/log retained")

    # Matching basename also preserves the Mach-O signing identifier.
    proof = output / "source-proof"
    proof.mkdir()
    flags = ["-fobjc-arc", "-framework", "AppKit", "-framework", "CoreAudio", "-framework", "Foundation"]
    run("original-build", ["clang", str(source), *flags, "-o", str(proof / "bt_proxy_speech_once")])
    require_identity(proof / "bt_proxy_speech_once", ORIGINAL_BINARY_SHA)
    local_source = output / "bt_proxy_speech_once.m"
    local_source.write_text(source.read_text().replace(str(dependency), "native_dual_sound.m"))
    shutil.copyfile(dependency, output / "native_dual_sound.m")
    for name in ("proxy_registry.h", "registry_check.m"):
        shutil.copyfile(HERE / name, output / name)
    shutil.copyfile(source.parent / "sync_once.py", output / "original_sync_once.py")
    run("patch-check", ["git", "apply", "--check", "--unidiff-zero", str(HERE / "player.patch")], output)
    run("patch", ["git", "apply", "--unidiff-zero", str(HERE / "player.patch")], output)
    (output / "assets").mkdir()
    for name in FIXTURES:
        shutil.copyfile(assets / name, output / "assets" / name)
    run("derived-build", ["clang", str(local_source), *flags, "-o", str(output / "bt_proxy_registered")])
    run("admission-build", ["clang", "-fobjc-arc", "-Werror", str(output / "registry_check.m"),
                             "-framework", "Foundation", "-o", str(output / "registry_check")])
    for name in FIXTURES:
        run("admission-" + name, [str(output / "registry_check"), str(output / "assets"), name])
    for path in output.rglob("*"):
        if path.is_file() and path.name != "build.json":
            receipt["files"][str(path.relative_to(output))] = sha(path)
    receipt["original_sources"] = {path.name: expected for path, expected in originals.items()}
    receipt["git_head"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=HERE, text=True).strip()
    receipt["device_execution"] = "NOT_RUN"
    (output / "build.json").write_text(json.dumps(receipt, indent=2))
    for path, expected in originals.items():
        require_identity(path, expected)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = prepare(args.source, args.assets, args.output)
    print(json.dumps({"status": "PASS_BUILD_AND_ADMISSION_ONLY", "device_execution": "NOT_RUN",
                      "player_sha256": result["files"]["bt_proxy_registered"]}))
