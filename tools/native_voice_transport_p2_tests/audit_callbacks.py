"""Walk the uninstrumented callback call graph in Clang IR, without creating an Engine."""

from pathlib import Path
import re
import subprocess

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
    print(f"native_voice_p2_callback_ir_{opt[1:]}_functions={len(visited)}")


for level in ("-O0", "-O2"):
    audit(level)
print("native_voice_p2_callback_ir=PASS")
