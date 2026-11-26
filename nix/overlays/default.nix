final: _prev:
let
  upstreamPkgs = import final.path {
    system = final.stdenv.hostPlatform.system;
    inherit (final) config;
  };
in
{
  # Nightly Neovim must not change plugin/grammar check dependencies and cache keys.
  vimPlugins = upstreamPkgs.vimPlugins // {
    obsidian-nvim = final.callPackage ../packages/obsidian-nvim.nix {
      inherit (upstreamPkgs.vimPlugins) obsidian-nvim;
    };
  };
  git-project = final.callPackage ../packages/git-project.nix { };
  git-readonly = final.callPackage ../packages/git-readonly.nix { };
  marksman = final.callPackage ../packages/marksman-bin.nix { };
  pam-tid-look = final.callPackage ../packages/pam-tid-look.nix { };
}
