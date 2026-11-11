{
  lib,
  pkgs,
  ...
}: let
  requirePackage = name:
    if builtins.hasAttr name pkgs
    then builtins.getAttr name pkgs
    else
      throw ''
        homeModules.common requires packages provided by overlays.default;
        apply the exported overlay to the Home Manager package set
      '';
in {
  home.packages = [
    pkgs._1password-cli
    pkgs.actionlint
    pkgs.claude-code
    pkgs.markdownlint-cli
    pkgs.openssl
    pkgs.tokei
    pkgs.tree
    pkgs.wget
    (requirePackage "git-project")
    (requirePackage "git-readonly")
  ];

  assertions = [
    {
      assertion = lib.getName pkgs._1password-cli == "1password-cli";
      message = "The common package policy expects the 1Password CLI package";
    }
  ];
}
