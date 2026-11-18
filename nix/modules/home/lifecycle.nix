{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.rebuild;
  inlineShellLibrary = import ../../lib/inline-shell-library.nix { inherit lib; };
  script = inlineShellLibrary ../../../bin/rebuild ../../../bin/lib/profile.sh;
  # An exported DOTFILES_COMMIT_MODEL still wins over the profile's choice.
  commitModelDefault = lib.optionalString (cfg.commitModel != null) ''
    : "''${DOTFILES_COMMIT_MODEL:=${lib.escapeShellArg cfg.commitModel}}"
  '';
  rebuild = pkgs.writeShellApplication {
    name = "rebuild";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      pkgs.nix
    ];
    text = commitModelDefault + script;
  };
in
{
  options.dotfiles.rebuild.commitModel = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "openai/gpt-6.2-astra";
    description = ''
      Pi model that writes rebuild commit subjects. Pi runs without
      extensions for this, so pick a model this account can use without them;
      null keeps Pi's own default.
    '';
  };

  config.home.packages = [ rebuild ];
}
