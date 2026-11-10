final: _prev: {
  git-project = final.callPackage ../packages/git-project.nix {};
  git-readonly = final.callPackage ../packages/git-readonly.nix {};
  marksman = final.callPackage ../packages/marksman-bin.nix {};
  rex-app = final.callPackage ../packages/rex-app.nix {};
}
