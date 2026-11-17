"""Exercise the real label script against strict fake Rex/Git executables only."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "bin/rex/label-window"
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["LABEL_FIXTURE"])
args = sys.argv[1:]
state = json.loads((root / "mock.json").read_text())
if pathlib.Path(sys.argv[0]).name == "rex":
    session, block, window = "fixture-session", "fixture-block", os.environ["FIXTURE_WINDOW"]
    if args == ["block", "inspect", "-s", session, block, "--json"]:
        if state.get("unavailable"): sys.exit(4)
        print(json.dumps({"block": {"window_id": window}}))
    elif args == ["session", "inspect", session, "--json"]:
        print(json.dumps({"windows": [{"window_id": window, "label": state["label"]}]}))
    elif args[:5] == ["window", "rename", "-s", session, window] and len(args) == 6:
        state["label"] = args[5]
        (root / "mock.json").write_text(json.dumps(state))
        with (root / "renames.jsonl").open("a") as out: out.write(json.dumps(args) + "\n")
    else: raise RuntimeError("Unexpected Rex call: " + repr(args))
else:
    if args[0] != "-C": raise RuntimeError("Git must select a directory")
    if state.get("nonrepo"): sys.exit(128)
    if args[2:] == ["rev-parse", "--show-toplevel"]: print("/fixture/project")
    elif args[2:] == ["rev-parse", "--path-format=absolute", "--git-common-dir"]: print("/fixture/project/.git")
    elif args[2:] == ["branch", "--show-current"]: print(state.get("branch", "feature"))
    else: raise RuntimeError("Unexpected Git call: " + repr(args))
'''


class RexLabels(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rex-label-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cwd = self.root / "workspace"
        self.cwd.mkdir()
        for name in ("rex", "git"):
            executable = self.root / name
            executable.write_text(MOCK.replace("#!/usr/bin/env python3", f"#!{sys.executable}", 1))
            executable.chmod(0o700)
        self.env = {**os.environ, "REX_SESSION": "fixture-session", "REX_BLOCK": "fixture-block",
                    "FIXTURE_WINDOW": "fixture-window", "LABEL_FIXTURE": str(self.root),
                    "REX_BIN_PATH": str(self.root / "rex"), "GIT_BIN_PATH": str(self.root / "git"),
                    "XDG_STATE_HOME": str(self.root / "state"), "HOME": str(self.root)}
        self.env.pop("REX_SERVER", None)
        self.set_state(label="Window deadbeef", branch="feature")

    def set_state(self, **changes):
        file = self.root / "mock.json"
        state = json.loads(file.read_text()) if file.exists() else {}
        file.write_text(json.dumps({**state, **changes}))

    def run_label(self):
        subprocess.run(["bash", str(SCRIPT), str(self.cwd)], env=self.env, check=True,
                       capture_output=True, text=True, timeout=10)
        return json.loads((self.root / "mock.json").read_text())["label"]

    def renames(self):
        file = self.root / "renames.jsonl"
        return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []

    def state_file(self):
        return self.root / "state/rex/window-labels.tsv"

    def test_default_window(self):
        self.assertEqual(self.run_label(), "project · feature")

    def test_managed_id_survives_relabel_and_reload(self):
        self.set_state(label="subagent-a1b2c3d4")
        self.assertEqual(self.run_label(), "Agent · project · feature · a1b2c3d4")
        self.set_state(branch="second")
        self.assertEqual(self.run_label(), "Agent · project · second · a1b2c3d4")
        self.assertEqual(self.run_label(), "Agent · project · second · a1b2c3d4")
        self.assertEqual(len(self.renames()), 2)
        self.assertEqual(self.state_file().read_text().splitlines()[0].split("\t")[3], "a1b2c3d4")
        self.assertEqual(self.state_file().stat().st_mode & 0o777, 0o600)

    def test_custom_label_after_automatic_label_is_preserved(self):
        self.set_state(label="subagent-a1b2c3d4")
        self.run_label()
        self.set_state(label="Agent · my human label", branch="changed")
        self.assertEqual(self.run_label(), "Agent · my human label")
        self.assertEqual(len(self.renames()), 1)

    def test_custom_subagent_label_is_not_generated_identity(self):
        self.set_state(label="subagent-my-important-task")
        self.assertEqual(self.run_label(), "subagent-my-important-task")
        self.assertEqual(self.renames(), [])

    def test_long_names_keep_suffix_within_limit(self):
        self.set_state(label="subagent-a1b2c3d4", branch="long-" + "x" * 200)
        label = self.run_label()
        self.assertEqual(len(label), 128)
        self.assertTrue(label.endswith(" · a1b2c3d4"))
        self.set_state(branch="different-" + "x" * 200)
        self.assertTrue(self.run_label().endswith(" · a1b2c3d4"))

    def test_legacy_three_column_record_preserves_agent_without_inventing_id(self):
        previous = "Agent · project · old"
        self.set_state(label=previous)
        file = self.state_file()
        file.parent.mkdir(parents=True)
        file.write_text(f"fixture-session\tfixture-window\t{previous}\n")
        self.assertEqual(self.run_label(), "Agent · project · feature")

    def test_separate_workers_remain_distinguishable(self):
        self.set_state(label="subagent-11111111")
        first = self.run_label()
        self.env["FIXTURE_WINDOW"] = "fixture-second"
        self.set_state(label="subagent-22222222")
        second = self.run_label()
        self.assertNotEqual(first, second)
        self.assertEqual(len(self.state_file().read_text().splitlines()), 2)

    def test_nonrepo_directory(self):
        self.set_state(label="subagent-a1b2c3d4", nonrepo=True)
        self.assertEqual(self.run_label(), "Agent · workspace · a1b2c3d4")

    def test_outside_rex_is_noop(self):
        self.env.pop("REX_SESSION")
        self.assertEqual(self.run_label(), "Window deadbeef")
        self.assertEqual(self.renames(), [])

    def test_unavailable_rex_never_renames(self):
        self.set_state(unavailable=True)
        self.run_label()
        self.assertEqual(self.renames(), [])

    def test_invalid_saved_suffix_is_not_reused(self):
        previous = "Agent · project · old"
        self.set_state(label=previous)
        file = self.state_file()
        file.parent.mkdir(parents=True)
        file.write_text(f"fixture-session\tfixture-window\t{previous}\tinvalid\n")
        self.assertEqual(self.run_label(), "Agent · project · feature")


if __name__ == "__main__":
    unittest.main()
