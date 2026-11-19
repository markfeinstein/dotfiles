#!/usr/bin/env python3
"""Check git-readonly against a scratch repository: reads pass, writes are rejected, state is unchanged."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(sys.argv[1])
REJECTED = 64
failures: list[str] = []


def raw_git(repo: Path, *args: str, env: dict[str, str]) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], env=env, check=True, capture_output=True, text=True
    ).stdout


def run(argv: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT), *argv], env=env, capture_output=True, text=True)


def snapshot(repo: Path, env: dict[str, str]) -> tuple[str, str, str]:
    return (
        raw_git(repo, "for-each-ref", env=env),
        raw_git(repo, "config", "--local", "--list", env=env),
        raw_git(repo, "status", "--porcelain", env=env),
    )


def expect(label: str, condition: bool, detail: str = "") -> None:
    if not condition:
        failures.append(f"{label}: {detail}".rstrip(": "))


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    global_config = root / "global.gitconfig"
    global_config.write_text("[user]\n\tglobalonly = visible\n")
    env = {
        **os.environ,
        "GIT_CONFIG_GLOBAL": str(global_config),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test Author",
        "GIT_AUTHOR_EMAIL": "author@example.com",
        "GIT_COMMITTER_NAME": "Test Author",
        "GIT_COMMITTER_EMAIL": "author@example.com",
        "GIT_TERMINAL_PROMPT": "0",
    }
    repo = root / "repo"
    repo.mkdir()
    raw_git(repo, "init", "-q", "-b", "main", env=env)
    (repo / "tracked.txt").write_text("alpha\n")
    raw_git(repo, "add", "tracked.txt", env=env)
    raw_git(repo, "commit", "-q", "-m", "first", env=env)
    (repo / "tracked.txt").write_text("alpha\nbeta\n")
    raw_git(repo, "commit", "-q", "-a", "-m", "second", env=env)
    raw_git(repo, "branch", "feature/one", env=env)
    raw_git(repo, "tag", "v1", env=env)
    subprocess.run(
        ["git", "clone", "-q", "--bare", str(repo), str(root / "remote.git")], env=env, check=True, capture_output=True
    )
    raw_git(repo, "remote", "add", "origin", str(root / "remote.git"), env=env)
    # Local config that would run a program during ls-remote; git-readonly must override it.
    marker = root / "ran-a-program"
    raw_git(repo, "config", "--local", "remote.origin.uploadpack", f"touch {marker}", env=env)
    raw_git(repo, "config", "--local", "core.sshCommand", f"touch {marker}", env=env)
    raw_git(repo, "config", "--local", "credential.helper", f"!touch {marker}", env=env)
    raw_git(repo, "config", "--local", "protocol.ext.allow", "always", env=env)
    raw_git(repo, "remote", "add", "extremote", f"ext::touch {marker}", env=env)
    raw_git(repo, "config", "--local", f"url.ext::touch {marker} #.insteadOf", "https://sneaky.example/", env=env)
    raw_git(repo, "remote", "add", "sneaky", "https://sneaky.example/repo.git", env=env)
    raw_git(repo, "update-ref", "refs/remotes/origin/main", "HEAD", env=env)
    raw_git(repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main", env=env)
    raw_git(repo, "config", "--local", "test.key", "value", env=env)
    raw_git(repo, "config", "--local", "core.hooksPath", "local-hooks", env=env)
    raw_git(repo, "config", "--local", "--add", "test.multi", "one", env=env)
    raw_git(repo, "config", "--local", "--add", "test.multi", "two", env=env)
    raw_git(repo, "config", "--local", "test.flag", "true", env=env)
    raw_git(repo, "config", "--local", "test.number", "7", env=env)
    raw_git(repo, "config", "--local", "alias.worktrunk", "status", env=env)
    (repo / "untracked.txt").write_text("untracked\n")
    (repo / "orderfile.txt").write_text("tracked.txt\n")
    head = raw_git(repo, "rev-parse", "HEAD", env=env).strip()
    git_dir = repo / ".git"
    config_file = git_dir / "config"

    allowed: list[list[str]] = [
        ["rev-list", "--count", "HEAD"],
        ["rev-list", "--left-right", "--count", "main...origin/main"],
        ["rev-list", "--reverse", "HEAD~1..HEAD"],
        ["config", "--get", "test.key"],
        ["config", "--get-all", "test.multi"],
        ["config", "--get-regexp", "^test\\."],
        ["config", "--get-regexp", "worktrunk|alias"],
        ["config", "--show-origin", "--get-regexp", "^(test|alias)\\."],
        ["config", "--get-urlmatch", "test.key", "https://example.com"],
        ["config", "--list"],
        ["config", "-l"],
        ["config", "--list", "--show-origin", "--show-scope", "--name-only"],
        ["config", "--list", "-z"],
        ["config", "--list", "--null"],
        ["config", "--list", "--local"],
        ["config", "--list", "--worktree"],
        ["config", "--list", "--file", str(config_file)],
        ["config", "--list", f"--file={config_file}"],
        ["config", "--list", "-f", str(config_file)],
        ["config", "--get", "--type", "bool", "test.flag"],
        ["config", "--get", "--type=bool", "test.flag"],
        ["config", "--get", "--bool", "test.flag"],
        ["config", "--get", "--int", "test.number"],
        ["config", "--get", "--path", "core.hooksPath"],
        ["config", "--get", "--default", "fallback", "test.missing"],
        ["config", "--get", "--default=fallback", "test.missing"],
        ["config", "test.key"],
        ["config", "get", "test.key"],
        ["config", "get", "--all", "test.multi"],
        ["config", "get", "--regexp", "^test\\."],
        ["config", "get", "--show-names", "test.key"],
        ["config", "list"],
        ["config", "list", "--show-origin", "--local"],
        ["branch", "-v"],
        ["branch", "-vv"],
        ["branch", "--verbose"],
        ["branch", "--list", "-v"],
        ["branch", "-v", "--list", "feature/*"],
        ["branch", "--list", "--verbose", "--verbose"],
        ["branch", "-a", "-vv"],
        ["branch", "-r", "-v", "--list", "origin/*"],
        ["branch", "--contains", "HEAD", "-v"],
        ["cat-file", "-t", head],
        ["cat-file", "-s", head],
        ["cat-file", "-e", head],
        ["cat-file", "-p", head],
        ["cat-file", "-p", "HEAD:tracked.txt"],
        ["count-objects"],
        ["count-objects", "-v"],
        ["count-objects", "-H"],
        ["count-objects", "-v", "-H"],
        ["reflog"],
        ["reflog", "show"],
        ["reflog", "exists", "HEAD"],
        ["symbolic-ref", "HEAD"],
        ["symbolic-ref", "-q", "HEAD"],
        ["symbolic-ref", "--quiet", "--short", "HEAD"],
        ["symbolic-ref", "refs/remotes/origin/HEAD"],
        ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
        ["log", "-1", "--format=%an <%ae>"],
        ["grep", "-n", "-E", "alpha|beta", "--", "tracked.txt"],
        ["status", "--porcelain"],
        ["grep", "-n", "-E", "-eOK|alpha", "--", "tracked.txt"],
        ["grep", "-n", "-i", "-E", "OK|alpha", "--", "tracked.txt"],
        ["diff", "-Oorderfile.txt", "HEAD~1", "HEAD"],
        ["log", "-1", "-Oorderfile.txt", "--stat"],
        ["show", "-Oorderfile.txt", "--stat", "HEAD"],
        ["ls-remote", "origin"],
        ["ls-remote", "--heads", "origin"],
        ["ls-remote", "-h", "-q", "origin", "main"],
        ["ls-remote", "--tags", "--refs", "origin", "v1"],
        ["ls-remote", "--exit-code", "origin", "main"],
        ["ls-remote", "--symref", "origin", "HEAD"],
        ["ls-remote", "--sort=refname", "origin"],
    ]
    rejected: list[list[str]] = [
        ["config", "set", "test.key", "other"],
        ["config", "unset", "test.key"],
        ["config", "--add", "test.multi", "three"],
        ["config", "--unset", "test.key"],
        ["config", "--unset-all", "test.multi"],
        ["config", "--replace-all", "test.multi", "three"],
        ["config", "--rename-section", "test", "renamed"],
        ["config", "--remove-section", "test"],
        ["config", "--edit"],
        ["config", "-e"],
        ["config", "rename-section", "test", "renamed"],
        ["config", "remove-section", "test"],
        ["config", "edit"],
        ["config", "test.key", "other"],
        ["config", "test.new", "created"],
        ["config", "--type=bool", "test.flag", "false"],
        ["config", "--local", "test.new", "created"],
        ["config", "--get-urlmatch", "test.key"],
        ["config", "--get", "--list"],
        ["config", "--list", "test.key"],
        ["config", "--global", "--list"],
        ["config", "--system", "--list"],
        ["config"],
        ["config", "--get"],
        ["config", "get"],
        ["config", "list", "test.key"],
        ["config", "--list", "--file"],
        ["branch", "-v", "newbranch"],
        ["branch", "-vv", "newbranch"],
        ["branch", "--verbose", "newbranch"],
        ["branch", "newbranch"],
        ["branch", "-d", "feature/one"],
        ["branch", "-D", "feature/one"],
        ["branch", "-m", "feature/one", "feature/two"],
        ["cat-file", "-p"],
        ["cat-file", head],
        ["cat-file", "--batch"],
        ["cat-file", "-p", head, head],
        ["cat-file", "-w", "--stdin"],
        ["count-objects", "-x"],
        ["count-objects", "extra"],
        ["reflog", "expire", "--all"],
        ["reflog", "delete", "HEAD@{0}"],
        ["reflog", "exists"],
        ["reflog", "exists", "HEAD", "extra"],
        ["symbolic-ref", "HEAD", "refs/heads/feature/one"],
        ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/other"],
        ["symbolic-ref", "-d", "refs/remotes/origin/HEAD"],
        ["symbolic-ref", "--delete", "refs/remotes/origin/HEAD"],
        ["symbolic-ref", "-m", "reason", "HEAD", "refs/heads/feature/one"],
        ["symbolic-ref"],
        ["grep", "-O", "alpha"],
        ["grep", "-Otrue", "alpha"],
        ["grep", "-O", "true", "alpha"],
        ["grep", "-nOtrue", "alpha"],
        ["grep", "-inO", "alpha"],
        ["grep", "-n", "-Otrue", "alpha", "--", "tracked.txt"],
        ["grep", "--open-files-in-pager", "alpha"],
        ["grep", "--open-files-in-pager=true", "alpha"],
        ["fetch"],
        ["fetch", "--dry-run"],
        ["ls-remote"],
        ["ls-remote", "--heads"],
        ["ls-remote", "nosuchremote"],
        ["ls-remote", str(root / "remote.git")],
        ["ls-remote", "https://example.com/repo.git"],
        ["ls-remote", f"--upload-pack=touch {marker}", "origin"],
        ["ls-remote", "-u", f"touch {marker}", "origin"],
        ["ls-remote", "--server-option=x", "origin"],
        ["ls-remote", "-o", "x", "origin"],
        ["ls-remote", "--get-url", "origin"],
        ["ls-remote", "extremote"],
        ["ls-remote", "sneaky"],
        ["merge-tree", "--write-tree", "HEAD", "feature/one"],
        ["log", "--output=out.txt"],
        ["log", "-1", "--format=%an;%ae"],
        ["log", "-1", "--format=%an&%ae"],
        ["log", "-1", "--format=`id`"],
        ["log", "-1", "--format=$(id)"],
        ["log", "-1", "--format=a\nb"],
        ["log", "-1", "--format=a\rb"],
    ]

    before = snapshot(repo, env)
    for argv in allowed:
        result = run(["-C", str(repo), *argv], env)
        expect(f"allowed {argv}", result.returncode == 0, f"exit {result.returncode}: {result.stderr.strip()}")
        expect(f"allowed {argv} leaves repo unchanged", snapshot(repo, env) == before)
    for argv in rejected:
        result = run(["-C", str(repo), *argv], env)
        expect(f"rejected {argv}", result.returncode == REJECTED, f"exit {result.returncode}: {result.stderr.strip()}")
        expect(f"rejected {argv} reports the rejection", "git-readonly:" in result.stderr, result.stderr.strip())
        expect(f"rejected {argv} leaves repo unchanged", snapshot(repo, env) == before)

    # Observable results, not only exit codes.
    def output(argv: list[str]) -> str:
        return run(["-C", str(repo), *argv], env).stdout

    expect("config --get returns the local value", output(["config", "--get", "test.key"]) == "value\n")
    expect(
        "config reports the real core.hooksPath, not a safety override",
        output(["config", "--get", "core.hooksPath"]) == "local-hooks\n",
        output(["config", "--get", "core.hooksPath"]),
    )
    expect("config get returns the local value", output(["config", "get", "test.key"]) == "value\n")
    expect("config --get-all lists every value", output(["config", "--get-all", "test.multi"]) == "one\ntwo\n")
    expect("config hides global values", output(["config", "--get", "user.globalonly"]) == "")
    expect(
        "config --list hides global values", "globalonly" not in output(["config", "--list"])
    )
    expect(
        "config --get-regexp keeps | inside the pattern",
        "alias.worktrunk status" in output(["config", "--get-regexp", "worktrunk|nomatch"]),
    )
    expect("rev-list --count counts commits", output(["rev-list", "--count", "HEAD"]) == "2\n")
    expect("branch -v shows subjects", "second" in output(["branch", "-v"]))
    expect("branch -vv lists branches", "feature/one" in output(["branch", "-vv"]))
    expect("cat-file -t prints the type", output(["cat-file", "-t", head]) == "commit\n")
    expect("cat-file -p prints the blob", output(["cat-file", "-p", "HEAD:tracked.txt"]) == "alpha\nbeta\n")
    expect("count-objects -v reports counts", "count:" in output(["count-objects", "-v"]))
    expect("reflog lists HEAD entries", "second" in output(["reflog"]))
    expect(
        "symbolic-ref reads a non-HEAD ref",
        output(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) == "origin/main\n",
    )
    expect(
        "ls-remote lists the remote's main branch",
        f"{head}\trefs/heads/main" in output(["ls-remote", "--heads", "origin"]),
        output(["ls-remote", "--heads", "origin"]),
    )
    expect("ls-remote never runs a program from local config", not marker.exists())
    expect("log keeps < and > in the format", output(["log", "-1", "--format=%an <%ae>"]) == "Test Author <author@example.com>\n")

    git_dir_flag = run(["--git-dir", str(git_dir), "rev-list", "--count", "HEAD"], env)
    expect("--git-dir DIR is accepted", git_dir_flag.returncode == 0 and git_dir_flag.stdout == "2\n", git_dir_flag.stderr)
    git_dir_equals = run([f"--git-dir={git_dir}", "rev-list", "--count", "HEAD"], env)
    expect("--git-dir=DIR is accepted", git_dir_equals.returncode == 0 and git_dir_equals.stdout == "2\n", git_dir_equals.stderr)
    git_dir_config = run(["--git-dir", str(git_dir), "config", "--get", "test.key"], env)
    expect("--git-dir DIR reads config", git_dir_config.stdout == "value\n", git_dir_config.stderr)

    for argv in (["--help"], ["-C", str(repo), "--help"], ["--no-pager", "--help"], ["--git-dir", str(git_dir), "--help"]):
        result = run(argv, env)
        expect(f"{argv[:1]} --help exits 0", result.returncode == 0, f"exit {result.returncode}: {result.stderr.strip()}")
        for phrase in ("rev-list", "config", "merge-tree", "ls-remote", "fetch", "Global and system config are hidden"):
            expect(f"--help mentions {phrase}", phrase in result.stdout)
    expect("--version still works", run(["--version"], env).stdout.startswith("git-readonly "))
    expect("empty argv is rejected", run([], env).returncode == REJECTED)
    expect("unknown global option is rejected", run(["--work-tree", str(repo), "status"], env).returncode == REJECTED)
    expect("-C without a subcommand is rejected", run(["-C", str(repo)], env).returncode == REJECTED)

if failures:
    print(f"{len(failures)} git-readonly check(s) failed:", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    raise SystemExit(1)
print("git-readonly checks passed")
