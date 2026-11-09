{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.openlogi;
  configTemplate = builtins.readFile ../../../openlogi/config.toml.in;
  deviceId =
    if cfg.deviceId == null
    then ""
    else cfg.deviceId;
in {
  options.dotfiles.openlogi = {
    enable = lib.mkEnableOption "the OpenLogi mouse configuration";

    deviceId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Machine-local OpenLogi device identifier, including the unit: prefix";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.deviceId != null && lib.hasPrefix "unit:" cfg.deviceId;
        message = "Enabled dotfiles.openlogi.deviceId must start with unit:";
      }
    ];

    xdg.configFile."openlogi/config.toml".text =
      builtins.replaceStrings
      ["@OPENLOGI_DEVICE_ID@"]
      [deviceId]
      configTemplate;
  };
}
