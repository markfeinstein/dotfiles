import os
import plistlib
import sys
import tempfile
from pathlib import Path

home = Path.home()
zwsp = "\u200b"
key_equivalents = {
    "Show Sidebar": zwsp,
    "Hide Sidebar": zwsp,
    "Show/Hide Sidebar": zwsp,
}
paths = [
    home / "Library/Preferences/.GlobalPreferences.plist",
]

for path in paths:
    try:
        try:
            with path.open("rb") as f:
                data = plistlib.load(f)
        except FileNotFoundError:
            data = {}

        current = data.setdefault("NSUserKeyEquivalents", {})
        changed = any(current.get(key) != value for key, value in key_equivalents.items())
        if not changed:
            print("unchanged")
            continue
        current.update(key_equivalents)
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
    except PermissionError as e:
        print(f"warning: could not update {path}: {e}", file=sys.stderr)
        print("unchanged")
