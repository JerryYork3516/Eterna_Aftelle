"""Export a frozen REF and a separately labelled patched copy; no executable is started."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from materials import prepare

FROZEN = "c64c7e2629ec775062fdc2ea1e4a934c73c1fa75"
PREFIX = "tools/apple_vp_reference_v1/"
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--resident", required=True)
    parser.add_argument("--proxy", required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    relative = output.relative_to(ROOT / ".build")
    if not relative.parts or output.exists():
        raise ValueError("output must be a NEW directory under this worktree .build")
    output.mkdir(parents=True, mode=0o700)
    files = git("ls-tree", "-r", "--name-only", FROZEN, "--", PREFIX).decode().splitlines()
    identities = {}
    for name in files:
        data = git("show", FROZEN+":"+name)
        identities[name] = hashlib.sha256(data).hexdigest()
        for copy in ["FROZEN_REF", "ADAPTED_REF"]:
            target = output / copy / name.removeprefix(PREFIX)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    target = (output / "ADAPTED_REF").relative_to(ROOT)
    patch = HERE / "ref-events.patch"
    for operation in [["--check"], []]:
        subprocess.run(["git", "apply", *operation, "--directory="+str(target), str(patch)],
                       cwd=ROOT, check=True)
    tests = output / "ADAPTED_REF/Tests/VPReferenceAudioTests"
    for name in ["ComparisonMaterialTests.swift"]:
        (tests / name).write_bytes((HERE / name).read_bytes())
    source = (ROOT / "apps/macos/Aftelle/AppController.swift").read_text()
    start = source.index("    private enum AppleVPAcousticWAV {")
    end = source.index("\n    }", start) + len("\n    }")
    extracted = source[start:end].replace("private enum AppleVPAcousticWAV", "enum AppleVPAcousticWAV", 1)
    (tests / "HostWAVParser.swift").write_text(
        "import CryptoKit\nimport Foundation\nenum AppleVPAcousticTestError: Error { case invalidFile }\n"+extracted+"\n")
    assert "(144_000 ... 288_000).contains(source.pcm.count)" in source
    prepare(args.resident, args.proxy, output / "assets")
    receipt = dict(schema_version=1, frozen_commit=FROZEN, source_commit=git("rev-parse","HEAD").decode().strip(),
                   frozen_files=identities, patch_sha256=hashlib.sha256(patch.read_bytes()).hexdigest(),
                   host_parser_sha256=hashlib.sha256(extracted.encode()).hexdigest(), device_execution=False)
    (output / "preparation.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print(json.dumps(dict(output=str(output), frozen_files=len(files), device_execution=False)))


if __name__ == "__main__":
    main()
