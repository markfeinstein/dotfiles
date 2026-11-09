#!/usr/bin/env bash

# Set canonical_repo_root and worktree_root only for an in-scope linked worktree.
prepare_worktree_context() {
  local repo_root=$1 wrong_repo_message=$2 outside_message=$3
  local common_git_dir_raw common_git_dir worktree_root_raw

  canonical_repo_root="$(realpath "$repo_root")"
  common_git_dir_raw="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n $common_git_dir_raw ]] || exit 0

  common_git_dir="$(realpath "$common_git_dir_raw")"
  if [[ $common_git_dir != "$canonical_repo_root/.git" ]]; then
    echo "$wrong_repo_message" >&2
    exit 1
  fi

  worktree_root_raw="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n $worktree_root_raw ]] || exit 0
  worktree_root="$(realpath "$worktree_root_raw")"
  case "$worktree_root" in
  "$canonical_repo_root"/*) ;;
  *)
    echo "$outside_message: $worktree_root" >&2
    exit 0
    ;;
  esac
}

# Consume Git's NUL-delimited worktree records without splitting path names.
for_each_live_worktree() {
  local callback=$1 field worktree_path='' worktree_bare=false worktree_prunable=false
  while IFS= read -r -d '' field; do
    case "$field" in
    worktree\ * | "")
      if [[ -n $worktree_path && $worktree_bare != true && $worktree_prunable != true ]]; then
        "$callback" "$worktree_path"
      fi
      worktree_path=
      worktree_bare=false
      worktree_prunable=false
      [[ $field != worktree\ * ]] || worktree_path=${field#worktree }
      ;;
    bare) worktree_bare=true ;;
    prunable*) worktree_prunable=true ;;
    esac
  done
  if [[ -n $worktree_path && $worktree_bare != true && $worktree_prunable != true ]]; then
    "$callback" "$worktree_path"
  fi
}
