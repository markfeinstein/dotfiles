final: _prev: {
  git-project = final.callPackage ../packages/git-project.nix {};
  git-readonly = final.callPackage ../packages/git-readonly.nix {};
}
