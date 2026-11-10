{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  managedByYabaiModule = options.programs ? yabai && config.programs.yabai.enable;
in {
  home.packages = lib.optionals (pkgs.stdenv.hostPlatform.isDarwin && !managedByYabaiModule) [
    pkgs.yabai
  ];
}
