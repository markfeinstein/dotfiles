{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  isDarwin = options ? system && options ? users && builtins.hasAttr "home-manager" options;
  isHomeManager = options ? home;
  inherit (config.profile.user) homeDirectory username;
in {
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

  config = lib.mkMerge (
    lib.optional isHomeManager {
      home = {
        username = lib.mkDefault username;
        homeDirectory = lib.mkDefault homeDirectory;
        stateVersion = lib.mkDefault "26.11";
      };
    }
    ++ lib.optional isDarwin {
      assertions = [
        {
          assertion = config.profile.name != null;
          message = "A Darwin profile must set profile.name";
        }
      ];

      system = {
        primaryUser = username;
        stateVersion = 6;
      };

      users.users.${username} = {
        name = username;
        home = homeDirectory;
      };

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;

        users.${username}.profile = {
          inherit (config.profile) name;
          user = lib.mkDefault config.profile.user;
        };
      };
    }
  );
}
