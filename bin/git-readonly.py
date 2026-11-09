#!/usr/bin/env python3
"""Run a bounded set of Git inspection commands without mutation-capable options."""

from __future__ import annotations

import os
import subprocess
import sys
from typing import NoReturn

VERSION = "1"
FORBIDDEN_FRAGMENTS = ("\0", "\n", "\r", ";", "|", "&", ">", "<", "`", "$(")
FORBIDDEN_OPTIONS = (
    "--ext-diff",
    "--open-files-in-pager",
    "--output",
    "--paginate",
    "--textconv",
)
DIFF_COMMANDS = {"diff", "log", "show"}
GENERIC_READ_COMMANDS = {
    "blame",
    "check-ignore",
    "describe",
    "diff",
    "diff-files",
    "diff-index",
    "diff-tree",
    "for-each-ref",
    "grep",
    "log",
    "ls-files",
    "ls-tree",
    "merge-base",
    "name-rev",
    "rev-parse",
    "show",
    "show-ref",
    "status",
}
BRANCH_READ_OPTIONS = (
    "--contains",
    "--format",
    "--list",
    "--merged",
    "--no-contains",
    "--no-merged",
    "--points-at",
    "--show-current",
    "-a",
    "-r",
)
TAG_READ_OPTIONS = ("--contains", "--format", "--list", "--merged", "--no-contains", "--no-merged", "--points-at", "-l")


def fail(message: str) -> NoReturn:
    print(f"git-readonly: {message}", file=sys.stderr)
    raise SystemExit(64)


def reject_unsafe_token(value: str) -> None:
    if any(fragment in value for fragment in FORBIDDEN_FRAGMENTS):
        fail(f"unsafe shell metacharacter in argument: {value!r}")
    for option in FORBIDDEN_OPTIONS:
        if value == option or value.startswith(option + "="):
            fail(f"option is not read-only: {value}")


def query_option(value: str, allowed: tuple[str, ...]) -> bool:
    return any(value == option or value.startswith(option + "=") for option in allowed)


def validate_subcommand(command: str, args: list[str]) -> None:
    for value in args:
        reject_unsafe_token(value)

    if command in GENERIC_READ_COMMANDS:
        return
    if command == "branch":
        if not args:
            return
        if all((not value.startswith("-")) or query_option(value, BRANCH_READ_OPTIONS) for value in args):
            if any(query_option(value, BRANCH_READ_OPTIONS) for value in args):
                return
        fail("branch is limited to listing and query options")
    if command == "remote":
        if not args or args == ["-v"]:
            return
        if args[0] == "get-url" and len(args) >= 2:
            return
        fail("remote is limited to listing and get-url")
    if command == "tag":
        if not args:
            return
        if all((not value.startswith("-")) or query_option(value, TAG_READ_OPTIONS) for value in args):
            if any(query_option(value, TAG_READ_OPTIONS) for value in args):
                return
        fail("tag is limited to listing and query options")
    if command == "worktree" and args and args[0] == "list":
        return
    if command == "reflog" and args and args[0] == "show":
        return
    if command == "stash" and args and args[0] in {"list", "show"}:
        return
    if command == "symbolic-ref":
        values = [value for value in args if value not in {"-q", "--quiet", "--short"}]
        if values == ["HEAD"]:
            return
        fail("symbolic-ref is limited to reading HEAD")
    fail(f"subcommand is not in the read-only contract: {command}")


def main() -> int:
    args = sys.argv[1:]
    if args == ["--version"]:
        print(f"git-readonly {VERSION}")
        return 0

    cwd: str | None = None
    if args[:1] == ["--no-pager"]:
        args = args[1:]
    if args[:1] == ["-C"]:
        if len(args) < 3:
            fail("-C requires a directory and subcommand")
        cwd = args[1]
        reject_unsafe_token(cwd)
        args = args[2:]
    if args[:1] == ["--no-pager"]:
        args = args[1:]
    if not args:
        fail("missing Git subcommand")
    if args[0].startswith("-"):
        fail(f"unsupported Git global option: {args[0]}")

    command, command_args = args[0], args[1:]
    reject_unsafe_token(command)
    validate_subcommand(command, command_args)

    git_args = [
        "git",
        "-c",
        "core.hooksPath=/dev/null",
        "-c",
        "core.fsmonitor=false",
        "-c",
        "core.pager=cat",
        "-c",
        "pager.branch=false",
        "-c",
        "pager.diff=false",
        "-c",
        "pager.log=false",
    ]
    if cwd is not None:
        git_args.extend(["-C", cwd])
    git_args.append(command)
    if command in DIFF_COMMANDS:
        git_args.extend(["--no-ext-diff", "--no-textconv"])
    git_args.extend(command_args)

    env = os.environ.copy()
    for name in list(env):
        if name in {"GIT_CONFIG", "GIT_CONFIG_COUNT"} or name.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")):
            env.pop(name, None)
    env.update(
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_CONFIG_SYSTEM=os.devnull,
        GIT_EXTERNAL_DIFF="",
        GIT_NO_LAZY_FETCH="1",
        GIT_OPTIONAL_LOCKS="0",
        GIT_PAGER="cat",
        GIT_TERMINAL_PROMPT="0",
    )
    return subprocess.run(git_args, env=env, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
