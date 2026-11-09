{
  coreutils,
  git,
  lib,
  writeShellApplication,
}: let
  inlineShellLibrary = import ../lib/inline-shell-library.nix {inherit lib;};
in
  writeShellApplication {
    name = "configure-repository-worktrees";
    runtimeInputs = [coreutils git];
    text = inlineShellLibrary ../../bin/configure-repository-worktrees ../../bin/lib/worktrees.sh;
  }
