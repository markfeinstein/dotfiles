#!/usr/bin/env python3
"""Return success when the current Dock preferences contain the managed values."""

from __future__ import annotations

import json
import os
import plistlib
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


def normalize_file_url(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    if value.startswith("file://"):
        value = unquote(urlparse(value).path)
    if value.startswith("/"):
        return os.path.normpath(value)
    return value


def subset_matches(current: Any, expected: Any) -> bool:
    if isinstance(expected, dict):
        return isinstance(current, dict) and all(
            key in current and subset_matches(current[key], value)
            for key, value in expected.items()
        )
    if isinstance(expected, list):
        return (
            isinstance(current, list)
            and len(current) == len(expected)
            and all(subset_matches(actual, wanted) for actual, wanted in zip(current, expected))
        )
    return current == expected


def tile_matches(current: Any, expected: Any) -> bool:
    if not isinstance(current, dict) or not isinstance(expected, dict):
        return False

    current_data = current.get("tile-data", {})
    expected_data = expected.get("tile-data", {})
    if not isinstance(current_data, dict) or not isinstance(expected_data, dict):
        return False

    expected_file_data = expected_data.get("file-data")
    if expected_file_data is not None:
        current_file_data = current_data.get("file-data")
        if not isinstance(current_file_data, dict) or not isinstance(expected_file_data, dict):
            return False
        if normalize_file_url(current_file_data.get("_CFURLString")) != normalize_file_url(
            expected_file_data.get("_CFURLString")
        ):
            return False

    expected_without_file_data = dict(expected)
    expected_tile_data = dict(expected_data)
    expected_tile_data.pop("file-data", None)
    expected_without_file_data["tile-data"] = expected_tile_data
    return subset_matches(current, expected_without_file_data)


def tile_list_matches(current: Any, expected: Any) -> bool:
    return (
        isinstance(current, list)
        and isinstance(expected, list)
        and len(current) == len(expected)
        and all(tile_matches(actual, wanted) for actual, wanted in zip(current, expected))
    )


def managed_preferences_match(current: dict[str, Any], expected: dict[str, Any]) -> bool:
    for key, expected_value in expected.items():
        if key not in current:
            return False
        current_value = current[key]
        if key in {"persistent-apps", "persistent-others"}:
            if not tile_list_matches(current_value, expected_value):
                return False
        elif not subset_matches(current_value, expected_value):
            return False
    return True


def read_current_preferences(path: str | None) -> dict[str, Any]:
    if path:
        with Path(path).open("rb") as handle:
            value = plistlib.load(handle)
    else:
        result = subprocess.run(
            ["/usr/bin/defaults", "export", "com.apple.dock", "-"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        value = plistlib.loads(result.stdout)
    if not isinstance(value, dict):
        raise ValueError("Dock preference domain is not a dictionary")
    return value


def main(argv: list[str]) -> int:
    if len(argv) not in {2, 3}:
        print(f"usage: {argv[0]} EXPECTED_JSON [CURRENT_PLIST]", file=sys.stderr)
        return 64
    try:
        expected = json.loads(Path(argv[1]).read_text())
        if not isinstance(expected, dict):
            raise ValueError("managed Dock preferences are not a dictionary")
        current = read_current_preferences(argv[2] if len(argv) == 3 else None)
    except (OSError, ValueError, json.JSONDecodeError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        print(f"could not compare managed Dock preferences: {error}", file=sys.stderr)
        return 1
    return 0 if managed_preferences_match(current, expected) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
