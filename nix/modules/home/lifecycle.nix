{
  lib,
  pkgs,
  ...
}: let
  inlineShellLibrary = import ../../lib/inline-shell-library.nix {inherit lib;};
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
    text = inlineShellLibrary ../../../bin/rebuild ../../../bin/lib/profile.sh;
  };
in {
  home.packages = [rebuild];
}
