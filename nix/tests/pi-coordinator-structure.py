"""Offline structural checks only; no model behavior, live tabs, or activation."""
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
SKILL = ROOT / "agents/skills/coordinator-workflow"


class CoordinatorStructure(unittest.TestCase):
    def test_frontmatter_and_size(self):
        text = (SKILL / "SKILL.md").read_text()
        self.assertTrue(text.startswith("---\n"))
        metadata, body = text[4:].split("\n---\n", 1)
        fields = dict(line.split(": ", 1) for line in metadata.splitlines())
        self.assertEqual(set(fields), {"name", "description"})
        self.assertEqual(fields["name"], SKILL.name)
        self.assertRegex(fields["name"], r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
        self.assertLessEqual(len(fields["name"]), 64)
        self.assertTrue(0 < len(fields["description"]) <= 1024)
        self.assertLess(len(body.splitlines()), 120)
        self.assertLess(len(body.split()), 1400)
        for target in re.findall(r"\]\(([^)]+)\)", body):
            self.assertFalse(target.startswith(("http:", "https:", "/")))
            self.assertTrue((SKILL / target).is_file())

    def test_scenario_shape_not_behavior(self):
        data = json.loads((SKILL / "evals/cases.json").read_text())
        self.assertIn("unexecuted", data["status"])
        cases = data["cases"]
        self.assertEqual(len(cases), len({case["id"] for case in cases}))
        self.assertGreaterEqual(len(cases), 10)
        self.assertTrue(any(not case["activate"] for case in cases))
        for case in cases:
            self.assertIsInstance(case["activate"], bool)
            self.assertTrue(case["prompt"])
            self.assertTrue(case["expected"])
            self.assertTrue(all(isinstance(item, str) and item for item in case["expected"]))

    def test_no_executable_or_remote_runtime_payload(self):
        runtime = [file.relative_to(SKILL).as_posix() for file in SKILL.rglob("*")
                   if file.is_file() and "evals" not in file.relative_to(SKILL).parts]
        self.assertEqual(runtime, ["SKILL.md"])
        text = (SKILL / "SKILL.md").read_text()
        self.assertNotRegex(text, r"curl\s|wget\s|/Users/|allowed-tools:")

    def test_no_unsafe_permission_default(self):
        settings = (ROOT / "nix/modules/home/pi/settings.nix").read_text()
        self.assertIn('defaultProjectTrust = "ask";', settings)
        instructions = (ROOT / "agents/global-instructions.md").read_text()
        for invariant in ["interactive approval gate", "Never force-push", "Do not run `rebuild`", "Managed children must not delegate further"]:
            self.assertIn(invariant, instructions)


if __name__ == "__main__":
    unittest.main()
