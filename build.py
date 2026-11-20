"""Bundle src/ into dist/RagdollSoccer.lua and copy it into the executor workspace.

    python build.py            build + deploy
    python build.py --no-deploy
Run it in the executor with:
    loadstring(readfile("RagdollSoccer/RagdollSoccer.lua"))()
"""
import shutil
import sys
from pathlib import Path

root = Path(__file__).parent
WORKSPACE = Path.home() / "AppData" / "Local" / "athena" / "workspace" / "RagdollSoccer"

# dependencies first; src/main.lua runs last
ORDER = [
    "lib/logo", "lib/icons", "lib/sfx", "lib/ui", "lib/config",
    "game/log", "game/world", "game/net", "game/input", "game/rules", "game/speed", "game/kick", "game/bot",
]

version = (root / "VERSION").read_text(encoding="utf8").strip()
out = [
    "-- Ragdoll Soccer v" + version + " (bundled by build.py)",
    "local __env = getgenv and getgenv() or _G",
    f'__env.RSVersion = "{version}"',
    "local __mods, __cache = {}, {}",
    "local function __import(n)",
    "\tif __cache[n] == nil then __cache[n] = __mods[n]() end",
    "\treturn __cache[n]",
    "end",
    "",
]
for name in ORDER:
    body = (root / "src" / f"{name}.lua").read_text(encoding="utf8")
    out.append(f'__mods["{name}"] = function()\n{body}\nend\n')
out.append("-- main")
out.append((root / "src" / "main.lua").read_text(encoding="utf8"))

dist = root / "dist"
dist.mkdir(exist_ok=True)
target = dist / "RagdollSoccer.lua"
target.write_text("\n".join(out), encoding="utf8")
print("built", target, f"({target.stat().st_size // 1024} KB)")

if "--no-deploy" not in sys.argv:
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    shutil.copy(target, WORKSPACE / "RagdollSoccer.lua")
    print("deployed to", WORKSPACE)
