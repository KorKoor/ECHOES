"""Compile every .lua file in the repo and fail on syntax errors. Needs `pip install lupa`."""
import glob
import os
import sys

try:
    from lupa.lua51 import LuaRuntime  # the game runs a Lua 5.1 dialect (Kahlua)
    DIALECT = '5.1'
except ImportError:
    from lupa import LuaRuntime
    DIALECT = 'default'

root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
lua = LuaRuntime()
check = lua.eval("function(s) local f, e = (loadstring or load)(s); return e end")
print("Lua dialect:", DIALECT)
bad = 0
for path in sorted(glob.glob(os.path.join(root, "**", "*.lua"), recursive=True)):
    err = check(open(path, encoding="utf8").read())
    if err:
        bad += 1
        print("SYNTAX ERROR %s: %s" % (os.path.relpath(path, root), err))
print("checked; %d syntax error(s)" % bad)
sys.exit(1 if bad else 0)
