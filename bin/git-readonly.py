#!/usr/bin/env python3
"""Run a bounded set of Git inspection commands without mutation-capable options."""

from __future__ import annotations

import os
import subprocess
import sys
from typing import NoReturn

VERSION = "2"
FORBIDDEN_FRAGMENTS = ("\0", "\n", "\r", ";", "&", "`", "$(")
FORBIDDEN_OPTIONS = (
    "--ext-diff",
    "--open-files-in-pager",
    "--output",
    "--paginate",
    "--textconv",
)
# git grep short options whose remaining characters are a value, not more flags.
GREP_ATTACHED_VALUE_OPTIONS = "efABCm"
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
    "rev-list",
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
BRANCH_VERBOSE_OPTIONS = ("-v", "-vv", "--verbose")
CAT_FILE_MODES = ("-t", "-s", "-e", "-p")
COUNT_OBJECTS_OPTIONS = ("-v", "-H")
SYMBOLIC_REF_READ_OPTIONS = ("-q", "--quiet", "--short")
CONFIG_WRITE_FORMS = (
    "--add",
    "--edit",
    "--remove-section",
    "--rename-section",
    "--replace-all",
    "--unset",
    "--unset-all",
    "-e",
    "edit",
    "remove-section",
    "rename-section",
    "set",
    "unset",
)
CONFIG_GET_MODES = ("--get", "--get-all", "--get-regexp", "--get-urlmatch")
CONFIG_LIST_MODES = ("--list", "-l")
CONFIG_FLAGS = (
    "--bool",
    "--int",
    "--local",
    "--name-only",
    "--null",
    "--path",
    "--show-origin",
    "--show-scope",
    "--worktree",
    "-z",
)
CONFIG_VALUE_OPTIONS = ("--default", "--file", "--type", "-f")
CONFIG_GET_SUBCOMMAND_FLAGS = ("--all", "--fixed-value", "--regexp", "--show-names")
CONFIG_GET_SUBCOMMAND_VALUE_OPTIONS = ("--url", "--value")
TAG_READ_OPTIONS = ("--contains", "--format", "--list", "--merged", "--no-contains", "--no-merged", "--points-at", "-l")


HELP = """\
git-readonly: run bounded, read-only Git inspection commands.

usage: git-readonly [--no-pager] [-C DIR] [--git-dir DIR] COMMAND [ARGS...]

Global options: --no-pager, -C DIR, --git-dir DIR (or --git-dir=DIR). --help and
--version are accepted before COMMAND.

Allowed commands:
  blame check-ignore describe diff diff-files diff-index diff-tree for-each-ref
  grep log ls-files ls-tree merge-base name-rev rev-list rev-parse show
  show-ref status          any arguments except the blocked options below
  branch                   list only: bare, or with --list/-l, -a, -r, --contains,
                           --merged, --no-merged, --points-at, --format,
                           --no-contains, --show-current; -v, -vv and --verbose
                           only modify a listing (branch -v NAME is rejected)
  cat-file                 -t, -s, -e or -p with exactly one object
  config                   read forms only: --get, --get-all, --get-regexp,
                           --get-urlmatch, --list/-l, NAME, config get, config list;
                           modifiers --show-origin --show-scope --name-only -z
                           --null --type --bool --int --path --default --local
                           --worktree --file/-f. Writes (set, unset, --add,
                           --unset, --unset-all, --replace-all, --rename-section,
                           --remove-section, --edit and NAME VALUE) are rejected.
                           Global and system config are hidden, so they never
                           appear in the output.
  count-objects            -v and -H only
  reflog                   bare, show, or exists REF
  remote                   bare, -v, or get-url NAME
  stash                    list or show
  symbolic-ref             read one ref (-q, --quiet, --short); two arguments,
                           -d, --delete and -m are rejected
  tag                      list only (--list/-l, --contains, --merged, ...)
  worktree                 list

Blocked: fetch, ls-remote (network), merge-tree (writes objects), and every other
command. Blocked options: --ext-diff, --open-files-in-pager, --output, --paginate,
--textconv, and for grep every short -O form (-O, -Ocmd, -O cmd, -nOcmd), which runs
a pager command (diff, log and show may still use -O<orderfile>). Arguments may not contain NUL, newline, CR, backtick, $( , ; or &.
Arguments are passed to Git as an argv list without a shell, so | < > are allowed
(regexes, --format=%an <%ae>). Hooks, fsmonitor and pagers are disabled.
"""


SAFETY_CONFIG_ARGS = (
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
)


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


def validate_config(args: list[str]) -> None:
    """Accept only the read forms of git config, including the get and list subcommands."""
    subcommand = args[0] if args and args[0] in {"get", "list"} else None
    for value in args:
        if value in CONFIG_WRITE_FORMS:
            fail(f"config write form is not allowed: {value}")
    if subcommand is not None:
        args = args[1:]

    flags = CONFIG_FLAGS
    value_options = CONFIG_VALUE_OPTIONS
    if subcommand == "get":
        flags += CONFIG_GET_SUBCOMMAND_FLAGS
        value_options += CONFIG_GET_SUBCOMMAND_VALUE_OPTIONS

    modes: list[str] = []
    positionals: list[str] = []
    skip_value = False
    for value in args:
        if skip_value:
            skip_value = False
        elif value in flags or any(value.startswith(option + "=") for option in value_options if option.startswith("--")):
            continue
        elif value in value_options:
            skip_value = True
        elif subcommand is None and value in CONFIG_GET_MODES + CONFIG_LIST_MODES:
            modes.append(value)
        elif value.startswith("-"):
            fail(f"config option is not in the read-only contract: {value}")
        else:
            positionals.append(value)
    if skip_value:
        fail("config option is missing its value")

    if subcommand == "list":
        expected = range(0, 1)
    elif subcommand == "get":
        expected = range(1, 3)
    elif len(modes) > 1:
        fail("config accepts one read mode")
    elif modes and modes[0] in CONFIG_LIST_MODES:
        expected = range(0, 1)
    elif modes and modes[0] == "--get-urlmatch":
        expected = range(2, 3)
    elif modes:
        expected = range(1, 3)
    else:
        expected = range(1, 2)
    if len(positionals) not in expected:
        fail("config needs a read form: --get, --get-all, --get-regexp, --list, NAME, or get/list")


def reject_grep_pager_option(args: list[str]) -> None:
    """Reject git grep -O in any short-option cluster; it runs an arbitrary pager command."""
    for value in args:
        if value == "--":
            return
        if not value.startswith("-") or value.startswith("--"):
            continue
        for flag in value[1:]:
            if flag == "O":
                fail(f"option is not read-only: {value}")
            if flag in GREP_ATTACHED_VALUE_OPTIONS:
                break


def validate_subcommand(command: str, args: list[str]) -> None:
    for value in args:
        reject_unsafe_token(value)
    if command == "grep":
        reject_grep_pager_option(args)

    if command in GENERIC_READ_COMMANDS:
        return
    if command == "branch":
        rest = [value for value in args if value not in BRANCH_VERBOSE_OPTIONS]
        if not rest:
            return
        if all((not value.startswith("-")) or query_option(value, BRANCH_READ_OPTIONS) for value in rest):
            if any(query_option(value, BRANCH_READ_OPTIONS) for value in rest):
                return
        fail("branch is limited to listing and query options")
    if command == "cat-file":
        if len(args) == 2 and args[0] in CAT_FILE_MODES and not args[1].startswith("-"):
            return
        fail("cat-file is limited to -t, -s, -e or -p with one object")
    if command == "config":
        validate_config(args)
        return
    if command == "count-objects":
        if all(value in COUNT_OBJECTS_OPTIONS for value in args):
            return
        fail("count-objects is limited to -v and -H")
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
    if command == "reflog":
        if not args or args[0] == "show":
            return
        if args[0] == "exists" and len(args) == 2 and not args[1].startswith("-"):
            return
        fail("reflog is limited to show and exists")
    if command == "stash" and args and args[0] in {"list", "show"}:
        return
    if command == "symbolic-ref":
        values = [value for value in args if value not in SYMBOLIC_REF_READ_OPTIONS]
        if len(values) == 1 and not values[0].startswith("-"):
            return
        fail("symbolic-ref is limited to reading one ref")
    fail(f"subcommand is not in the read-only contract: {command}")


def main() -> int:
    args = sys.argv[1:]
    if args == ["--version"]:
        print(f"git-readonly {VERSION}")
        return 0

    global_args: list[str] = []
    while args:
        if args[0] == "--no-pager":
            args = args[1:]
        elif args[0] in {"-C", "--git-dir"}:
            if len(args) < 3:
                fail(f"{args[0]} requires a value and subcommand")
            reject_unsafe_token(args[1])
            global_args.extend(args[:2])
            args = args[2:]
        elif args[0].startswith("--git-dir="):
            reject_unsafe_token(args[0])
            global_args.append(args[0])
            args = args[1:]
        else:
            break
    if args[:1] == ["--help"]:
        print(HELP, end="")
        return 0
    if not args:
        fail("missing Git subcommand")
    if args[0].startswith("-"):
        fail(f"unsupported Git global option: {args[0]}")

    command, command_args = args[0], args[1:]
    reject_unsafe_token(command)
    validate_subcommand(command, command_args)

    git_args = ["git"]
    if command != "config":
        # Config reads must report real values, so only other commands get the overrides.
        git_args.extend(SAFETY_CONFIG_ARGS)
    git_args.extend(global_args)
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
