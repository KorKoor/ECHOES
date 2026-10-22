"""Line coverage of the Lua modules under the mocked-API scenario (both modes, a few seeds).

Not a quality proof (the mock is generous) but it shows which code the smoke test never reaches, and CI fails if the
overall figure drops below THRESHOLD, so new modules cannot silently go untested. Needs `pip install lupa`.
"""
import os
import re
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    from lupa import LuaRuntime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LUA_ROOT = os.path.join(ROOT, "Echoes", "42", "media", "lua")
THRESHOLD = 80
RUNS = [(1, "engine"), (2, "engine"), (1, "noengine"), (2, "noengine")]

hit = {}  # path -> set(lines)
for seed, mode in RUNS:
    lua = LuaRuntime()
    lua.globals().__sink = lambda *a: None
    lua.execute("print = function() end")
    lua.execute(
        """
        COV = {}
        debug.sethook(function(ev, line)
          local src = debug.getinfo(2, "S").source:gsub("\\\\", "/")
          if src and string.find(src, "Echoes/42", 1, true) then
            COV[src] = COV[src] or {}
            COV[src][line] = true
          end
        end, "l")
        """
    )
    lua.execute("SEED = %d; MODE = %r; BASE = %r" % (seed, mode, ROOT.replace("\\", "/")))
    try:
        lua.execute(open(os.path.join(ROOT, "tests", "mock_harness.lua")).read())
    except Exception as exc:  # noqa: BLE001
        print("run failed (%s %s): %s" % (seed, mode, exc))
        sys.exit(1)
    for src, lines in lua.eval("COV").items():
        hit.setdefault(src.lstrip("@").replace("\\", "/"), set()).update(lines.keys())

total = covered = 0
print("%-36s %s" % ("file", "covered"))
for dirpath, _, names in os.walk(LUA_ROOT):
    for name in sorted(names):
        if not name.endswith(".lua"):
            continue
        path = os.path.join(dirpath, name)
        code = open(path, encoding="utf8").read().split("\n")
        executable = [
            i + 1
            for i, line in enumerate(code)
            if line.strip()
            and not line.strip().startswith("--")
            and not re.match(r"^\s*(end|else|\}|\)|local function .*\))\s*[,)]*$", line.strip())
        ]
        got = [i for i in executable if any(i in lines for p, lines in hit.items() if p.endswith(os.path.relpath(path, ROOT).replace("\\", "/")))]
        total += len(executable)
        covered += len(got)
        pct = 100 * len(got) // max(1, len(executable))
        print("%-36s %3d/%3d %3d%%" % (os.path.relpath(path, LUA_ROOT), len(got), len(executable), pct))
pct = 100 * covered // max(1, total)
print("TOTAL %d/%d = %d%% (threshold %d%%)" % (covered, total, pct, THRESHOLD))
sys.exit(0 if pct >= THRESHOLD else 1)
