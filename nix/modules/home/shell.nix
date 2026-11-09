{
  config,
  lib,
  ...
}: let
  rosePineLsColors = import ../../lib/rose-pine-ls-colors.nix;
in {
  home = {
    sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
    ];

    sessionVariables = {
      EDITOR = lib.mkDefault "vi";
      VISUAL = lib.mkDefault "vi";
      LS_COLORS = rosePineLsColors;
    };

    shellAliases = {
      cat = "bat";
      p = "pi";
    };
  };
}
