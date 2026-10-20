"""Package the byte-identical ADAPTED_REF CLI for native window control; no execution."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil

from integration import REF_BINARY_SHA
from prepare_player import require_identity, sha


def prepare(reference, info, output):
    reference, info, output = map(lambda p: Path(p).absolute(), (reference, info, output))
    require_identity(reference, REF_BINARY_SHA)
    metadata = plistlib.loads(info.read_bytes())
    if metadata.get("CFBundleIdentifier") != "org.eterna.research.apple-vp-reference-v1":
        raise ValueError("Unexpected REF identity")
    resources = reference.resolve().parent / "AppleVPReferenceV1_VPReferenceAudio.bundle"
    if not resources.is_dir() or output.suffix != ".app":
        raise ValueError("REF resources or app destination invalid")
    before = {str(p.relative_to(resources)): sha(p) for p in resources.rglob("*") if p.is_file()}
    output.mkdir(parents=False, exist_ok=False)
    contents = output / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    executable = contents / "MacOS" / "apple-vp-reference"
    shutil.copy2(reference, executable)
    shutil.copytree(resources, contents / "Resources" / resources.name)
    metadata.update(CFBundleExecutable=executable.name, CFBundlePackageType="APPL")
    (contents / "Info.plist").write_bytes(plistlib.dumps(metadata))
    require_identity(executable, REF_BINARY_SHA)
    copied = contents / "Resources" / resources.name
    assert before == {str(p.relative_to(copied)): sha(p) for p in copied.rglob("*") if p.is_file()}
    receipt = dict(schema_version=1, binary_sha256=sha(executable), original_info_sha256=sha(info),
                   packaged_info_sha256=sha(contents / "Info.plist"), resources=before,
                   source_modified=False, device_execution="NOT_RUN")
    output.with_suffix(".receipt.json").write_text(json.dumps(receipt, indent=2))
    return executable


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--info", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(prepare(args.reference, args.info, args.output))
