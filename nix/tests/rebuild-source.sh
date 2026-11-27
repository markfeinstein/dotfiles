#!/usr/bin/env bash
# Usage: bash rebuild-source.sh REBUILD_SCRIPT (the inlined script, run with
# this shell so the stub below is found before the wrapper's pinned nix)
# Runs `rebuild doctor` against a stub `nix` and checks which flake source it
# selects. Nothing is built, fetched, or activated.
set -euo pipefail

rebuild=$1
root=$(cd "$(mktemp -d)" && pwd -P)
export HOME="$root/home"
mkdir -p "$HOME" "$root/bin"

# Use this shell for the stub and rebuild; a sandbox may lack bash on PATH.
printf '#!%s\n' "$BASH" >"$root/bin/nix"
cat >>"$root/bin/nix" <<'STUB'
case "$*" in
  --version) echo 'nix (stub)' ;;
  *--apply*) printf 'testhost\nwork\n' ;;
  *profile.name*) echo work ;;
  *primaryUser* | *home.username*) id -un ;;
  *homeDirectory* | *.home) echo "$HOME" ;;
  *) echo stub ;;
esac
STUB
chmod +x "$root/bin/nix"
export PATH="$root/bin:$PATH"

make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  touch "$1/flake.nix"
}
make_repo "$root/work-checkout"
make_repo "$root/other-checkout"

sources="$root/sources"
mkdir -p "$sources"
unset DOTFILES_FLAKE DOTFILES_PERSONAL_FLAKE DOTFILES_WORK_FLAKE DOTFILES_REPO
export DOTFILES_PROFILE=work DOTFILES_HOST=testhost DOTFILES_SOURCE_DIR="$sources"

expect() {
  local label=$1 expected=$2 output actual
  shift 2
  output=$(cd "$root" && env "$@" "$BASH" "$rebuild" doctor 2>&1) || {
    printf 'FAIL %s: rebuild exited non-zero\n%s\n' "$label" "$output" >&2
    exit 1
  }
  actual=$(sed -n 's/^Source: //p; s/^Mode: \([a-z]*\) .*/\1/p' <<<"$output" | paste -sd ' ' -)
  [[ "$actual" == "$expected" ]] || {
    printf 'FAIL %s: expected "%s", got "%s"\n%s\n' "$label" "$expected" "$actual" "$output" >&2
    exit 1
  }
  printf 'ok %s\n' "$label"
}

test_lockfile_commit_subject() {
  local repo="$root/lockfile-only" marker="$root/pi-called" subject
  mkdir -p "$repo" "$root/commit-tmp"
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config commit.gpgsign false
  printf '{}\n' >"$repo/flake.lock"
  git -C "$repo" add flake.lock

  (
    cd "$repo"
    eval "$(awk '/^commit_index\(\) \{/,/^\}/' "$rebuild")"
    manual_message=''
    commit_model=''
    tmp_dir="$root/commit-tmp"
    fallback_message=0
    committed=no
    fail() { printf 'FAIL lockfile-only commit: %s\n' "$*" >&2; exit 1; }
    confirm() { touch "$marker"; return 1; }
    pi() { touch "$marker"; return 1; }
    commit_index
  )

  subject=$(git -C "$repo" log -1 --format=%s)
  [[ "$subject" == 'chore(flake): update inputs' ]] || {
    printf 'FAIL lockfile-only commit: unexpected subject "%s"\n' "$subject" >&2
    exit 1
  }
  [[ ! -e "$marker" ]] || {
    printf 'FAIL lockfile-only commit: prompted or called Pi\n' >&2
    exit 1
  }
  printf 'ok lockfile-only commit skips Pi\n'
}

test_lockfile_commit_subject

expect 'no persisted source uses the default' 'github:markfeinstein/dotfiles/main remote'

printf '%s/\n' "$root/work-checkout" >"$sources/work"
expect 'persisted checkout beats the default' "$root/work-checkout local"
expect 'profile variable beats a persisted checkout' 'github:example/env remote' \
  DOTFILES_WORK_FLAKE=github:example/env
expect 'DOTFILES_REPO beats a persisted checkout' "$root/other-checkout local" \
  DOTFILES_REPO="$root/other-checkout"

printf 'github:example/persisted\n' >"$sources/work"
expect 'persisted remote flake beats the default' 'github:example/persisted remote'
