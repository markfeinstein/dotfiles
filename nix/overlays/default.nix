final: _prev: {
  configure-repository-worktrees = final.callPackage ../packages/configure-repository-worktrees.nix {};
  git-project = final.callPackage ../packages/git-project.nix {};
  git-readonly = final.callPackage ../packages/git-readonly.nix {};
}
