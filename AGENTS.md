# AGENTS

Repository-specific rules for agents working in this dotfiles repository. They
add to the global instructions and the `repository-workflow` skill.

## Local integration

- Fast-forward `main` when possible. When `main` has advanced (commonly a
  `rebuild` lockfile commit), a non-rewriting local merge commit is this
  repository's established strategy; do not ask. Never drop `main`'s
  `flake.lock` changes.
- Standing approval: once a task's checks pass, merging into local `main` and
  removing the task worktree and branch are pre-approved here. Push and rebuild
  still require an explicit request.

## Verification

- List the Nix checks and what they cover:
  `nix eval --json .#checks.aarch64-darwin --apply builtins.attrNames`.
  Names group by area: `home-*` and `darwin-*` evaluate the profile outputs,
  `pi-*` cover Pi configuration and the coordinator skill, `obsidian-*`,
  `neovim-*`, and `marksman-binary` cover the editor setup, `rebuild-source`
  covers `bin/rebuild` source selection, `rex-*` cover Rex labels, and
  `yabai-signed-app` covers the signed app. Run any
  newer checks the command lists for areas you change.
- Run one check: `nix build --no-link .#checks.aarch64-darwin.<name>`. Run
  `nix flake check --no-build` for a broad evaluation of every output and
  `nix fmt -- --ci` for Nix formatting (both run in CI; `nix fmt` fixes it).
- Rex Lua and Python tests live in `tests/rex/` and have no Nix check. Run them
  from the repository root when you change Rex scripts or pickers. `lua` is not
  on `PATH`, so use
  `nix shell --offline --inputs-from . nixpkgs#lua5_1 --command lua tests/rex/worktrees.lua`
  (Lua 5.1; the other `tests/rex/*.lua` files run the same way) and
  `python3 tests/rex/picker_focus.py`.
- Nix only sees tracked files: `git add` new files (intent-to-add is enough)
  before evaluating or building.

## Rebuild

- Personal profile from a local checkout, run from `main` after integration:
  `rebuild --profile personal --repo <path to the main worktree> --commit-message "<conventional commit subject>"`.
  Run it in a visible Rex split as the global instructions describe.
- Work hosts rebuild from their own profile repository, not from this one.

## Publishing

- Push only on explicit request, as a fast-forward of `main` to `origin`. First
  scan the unpushed commits with
  `gitleaks git --config .gitleaks.toml --redact --log-opts="origin/main..main"`
  and stop on any finding.
