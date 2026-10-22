"""Run the mocked-API smoke test (tests/mock_harness.lua) for several random seeds.

Needs `pip install lupa`. Exits non-zero if any run raises a Lua error or logs "[ERROR]".
This checks that the logic runs and does not crash against a fake game; it is NOT a game test.
"""
import os
import sys

try:
    from lupa.lua51 import LuaRuntime  # the game runs a Lua 5.1 dialect (Kahlua)
    DIALECT = '5.1'
except ImportError:
    from lupa import LuaRuntime
    DIALECT = 'default'

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SEEDS = range(1, int(sys.argv[1]) + 1) if len(sys.argv) > 1 else range(1, 13)
MODES = ("engine", "noengine")
failures = 0

for seed, mode in [(sd, md) for sd in SEEDS for md in MODES]:
    lua = LuaRuntime()
    out = []
    lua.globals().__append = out.append
    lua.execute(
        "print = function(...) local t = {} for i = 1, select('#', ...) do t[#t+1] = tostring((select(i, ...))) end "
        "__append(table.concat(t, '\\t')) end"
    )
    lua.execute("SEED = %d; MODE = %r; BASE = %r" % (seed, mode, ROOT.replace("\\", "/")))
    try:
        lua.execute(open(os.path.join(ROOT, "tests", "mock_harness.lua")).read())
    except Exception as exc:  # noqa: BLE001
        out.append("LUA ERROR: %s" % exc)
    bad = [l for l in out if "[ERROR]" in l or "LUA ERROR" in l]
    status = "FAIL" if bad else "ok"
    print("seed %2d %-8s: %s (%d lines)" % (seed, mode, status, len(out)))
    for l in bad[:5]:
        print("   ", l)
    failures += 1 if bad else 0

sys.exit(1 if failures else 0)
