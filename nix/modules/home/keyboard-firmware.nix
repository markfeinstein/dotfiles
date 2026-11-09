{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.keyboardFirmware;
in {
  options.dotfiles.keyboardFirmware = {
    enable = lib.mkEnableOption "personal keyboard firmware tooling";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [
        pkgs.gnumake
        pkgs.gnused
        pkgs.qmk
      ];
      description = "Personal keyboard firmware packages; project flakes own Zephyr and ZMK SDKs";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = cfg.packages;
  };
}
