import os
import plistlib
import sys
import tempfile
from pathlib import Path

if len(sys.argv) < 3 or sys.argv[2] not in {"enable", "disable"}:
    raise SystemExit("usage: set-macos-symbolic-hotkeys.py PLIST enable|disable [ID ...]")

path = Path(sys.argv[1])
enabled = sys.argv[2] == "enable"
keys = sys.argv[3:]

try:
    with path.open("rb") as f:
        data = plistlib.load(f)
except FileNotFoundError:
    data = {}

hotkeys = data.setdefault("AppleSymbolicHotKeys", {})
changed = False
for key in keys:
    entry = hotkeys.get(key)
    if not isinstance(entry, dict):
        entry = {}
        hotkeys[key] = entry
        changed = True
    if entry.get("enabled") is not enabled:
        entry["enabled"] = enabled
        changed = True

if not changed:
    print("unchanged")
    raise SystemExit(0)

path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
try:
    with os.fdopen(fd, "wb") as f:
        plistlib.dump(data, f)
    os.replace(tmp, path)
finally:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
print("changed")
