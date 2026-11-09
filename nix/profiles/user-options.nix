{
  config,
  lib,
  pkgs,
  ...
}: {
  options.profile = {
    name = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "personal"
        "work"
      ]);
      default = null;
      description = "Selected configuration profile";
    };

    user = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "mark";
        description = "Login username";
      };

      fullName = lib.mkOption {
        type = lib.types.str;
        default = "Mark Feinstein";
        description = "Full user name";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "mark.feinstein@gmail.com";
        description = "Primary Git email address";
      };

      homeDirectory = lib.mkOption {
        type = lib.types.str;
        default =
          if pkgs.stdenv.hostPlatform.isDarwin
          then "/Users/${config.profile.user.username}"
          else "/home/${config.profile.user.username}";
        description = "User home directory";
      };
    };
  };
}
