"""Walk the uninstrumented callback call graph in Clang IR, without creating an Engine."""

from pathlib import Path
import re
import subprocess
import sys

direct_vpio = sys.argv[1:] == ["--direct-vpio"]
same_frame = direct_vpio or sys.argv[1:] == ["--same-frame"]
assert not sys.argv[1:] or same_frame

src = Path(__file__).resolve().parents[2] / "apps/macos/NativeVoiceTransport"
symbol = r'@(?:"([^"]+)"|([\w.$]+))'
definition = re.compile(r"^define .*?" + symbol + r"\(.*?^\}", re.MULTILINE | re.DOTALL)
instruction = re.compile(r"\b(?:call|invoke|callbr)\s")
direct = re.compile(symbol + r"\(")
safe_intrinsics = ("llvm.lifetime.", "llvm.memset.", "llvm.memcpy.", "llvm.dbg.",
                   "llvm.is.fpclass.", "llvm.uadd.sat.", "llvm.fabs.", "llvm.umin.", "llvm.umax.", "llvm.smin.", "llvm.smax.")


def audit(opt):
    modules = []
    for name in ("NativeVoiceRing.c", "NativeVoiceRealtime.c", "NativeVoiceRealtimeLease.mm"):
        compiler = ["clang++", "-std=c++20", "-fobjc-arc"] if name.endswith(".mm") else ["clang", "-std=c11"]
        if same_frame:
            compiler.append("-DNATIVE_VOICE_SAME_FRAME_DIAGNOSTICS=1")
        if direct_vpio:
            compiler.append("-DNATIVE_VOICE_DIRECT_VPIO=1")
        ir = subprocess.check_output(
            [*compiler, opt, "-mmacosx-version-min=26.5", "-S", "-emit-llvm", str(src / name), "-o", "-"],
            text=True,
        )
        modules.append({m.group(1) or m.group(2): m.group(0) for m in definition.finditer(ir)})
    callbacks = [name for name in modules[2] if "block_invoke" in name]
    assert len(callbacks) == 2

    visited = set()

    def visit(module, name):
        key = module, name
        if key in visited:
            return
        visited.add(key)
        for line in modules[module][name].splitlines()[1:]:
            op = instruction.search(line.split(";")[0])
            if not op:
                continue
            target = direct.search(line[op.end():])
            assert target, (name, line)
            callee = target.group(1) or target.group(2)
            if direct_vpio and name == "nvt_direct_vpio_capture" and callee == "AudioUnitRender":
                continue  # The public pull is the native unit boundary.
            if callee in modules[module]:
                visit(module, callee)
            else:
                matches = [i for i, funcs in enumerate(modules) if callee in funcs]
                if len(matches) == 1:
                    visit(matches[0], callee)
                else:
                    assert callee in {"memcpy", "memset", "memmove"} or callee.startswith(safe_intrinsics), (name, callee)

    for callback in callbacks:
        visit(2, callback)
    if direct_vpio:
        for callback in ("nvt_direct_vpio_capture", "nvt_direct_vpio_render", "nvt_direct_vpio_changed"):
            visit(1, callback)
        print(f"native_voice_direct_vpio_callback_ir_{opt[1:]}_functions={len(visited)}")
    if same_frame and opt == "-O0":
        assert (1, "offer_same_frame") in visited
    print(f"native_voice_p2_callback_ir_{opt[1:]}_functions={len(visited)}")


for level in ("-O0", "-O2"):
    audit(level)
print("native_voice_p2_callback_ir=PASS")
