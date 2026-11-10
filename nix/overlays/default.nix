final: _prev: let
  upstreamPkgs = import final.path {
    system = final.stdenv.hostPlatform.system;
    inherit (final) config;
  };
in {
  # Nightly Neovim must not change plugin/grammar check dependencies and cache keys.
  vimPlugins = upstreamPkgs.vimPlugins;
  git-project = final.callPackage ../packages/git-project.nix {};
  git-readonly = final.callPackage ../packages/git-readonly.nix {};
  marksman = final.callPackage ../packages/marksman-bin.nix {};
  rex-app = final.callPackage ../packages/rex-app.nix {};
}
