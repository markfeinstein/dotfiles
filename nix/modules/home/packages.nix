{
  lib,
  pkgs,
  ...
}:
let
  requirePackage =
    name:
    if builtins.hasAttr name pkgs then
      builtins.getAttr name pkgs
    else
      throw ''
        homeModules.common requires packages provided by overlays.default;
        apply the exported overlay to the Home Manager package set
      '';
  # Link only timeout: the rest of coreutils would shadow macOS ls, date and stat.
  gnuTimeout = pkgs.runCommand "gnu-timeout" { meta.mainProgram = "timeout"; } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.coreutils}/bin/timeout "$out/bin/timeout"
  '';
in
{
  home.packages = [
    pkgs._1password-cli
    pkgs.actionlint
    pkgs.claude-code
    pkgs.markdownlint-cli
    pkgs.openssl
    pkgs.tokei
    pkgs.tree
    pkgs.wget
    gnuTimeout
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
