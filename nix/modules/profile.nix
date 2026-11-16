{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  isDarwin = options ? system && options ? users && builtins.hasAttr "home-manager" options;
  isHomeManager = options ? home;
  inherit (config.profile.user) homeDirectory username;
  vaultType = lib.types.listOf (
    lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.strMatching ".+";
          description = "Obsidian vault name";
        };
        path = lib.mkOption {
          type = lib.types.strMatching ".+";
          description = "Absolute or home-relative Obsidian vault path";
        };
      };
    }
  );
  vaults = config.profile.obsidian.vaults;
  profileAssertions =
    lib.optionals (vaults != null) [
      {
        assertion = lib.all (
          vault: lib.hasPrefix "/" vault.path || lib.hasPrefix "~/" vault.path
        ) vaults;
        message = "profile.obsidian.vaults paths must be absolute or start with ~/";
      }
      {
        assertion =
          lib.length (lib.unique (map (vault: vault.name) vaults)) == lib.length vaults;
        message = "profile.obsidian.vaults names must be unique";
      }
    ]
    ++ [
      {
        assertion = lib.all (
          selector: selector.item != null || selector.vault != null || selector.account != null
        ) config.profile.ssh.onePasswordAgent.keys;
        message = "profile.ssh.onePasswordAgent.keys entries must select an item, vault, or account";
      }
    ];
in
{
  options.profile = {
    name = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "personal"
          "work"
        ]
      );
      default = null;
      description = "Selected configuration profile";
    };

    obsidian.vaults = lib.mkOption {
      type = if isDarwin then lib.types.nullOr vaultType else vaultType;
      default = if isDarwin then null else [ ];
      description = ''
        Profile-owned Obsidian vaults available to consuming modules. On Darwin,
        null inherits the selected Home Manager profile fallback; an explicit
        list, including an empty list, replaces that fallback.
      '';
    };

    ssh.onePasswordAgent = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = pkgs.stdenv.hostPlatform.isDarwin;
        description = "Whether the profile uses the 1Password SSH agent";
      };

      keys = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              item = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching ".+");
                default = null;
                description = "1Password SSH key item name or ID";
              };
              vault = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching ".+");
                default = null;
                description = "1Password vault name or ID containing matching SSH keys";
              };
              account = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching ".+");
                default = null;
                description = "1Password account name or ID containing matching SSH keys";
              };
            };
          }
        );
        default = [ ];
        description = "Ordered selectors for SSH keys exposed by the 1Password agent";
      };
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
          if pkgs.stdenv.hostPlatform.isDarwin then
            "/Users/${config.profile.user.username}"
          else
            "/home/${config.profile.user.username}";
        description = "User home directory";
      };
    };
  };

  config = lib.mkMerge (
    lib.optional (isHomeManager || isDarwin) {
      assertions = profileAssertions;
    }
    ++ lib.optional isHomeManager {
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

        users.${username}.profile =
          {
            inherit (config.profile) name;
            ssh.onePasswordAgent = {
              enable = lib.mkDefault config.profile.ssh.onePasswordAgent.enable;
              keys = lib.mkDefault config.profile.ssh.onePasswordAgent.keys;
            };
            user = lib.mkDefault config.profile.user;
          }
          // lib.optionalAttrs (vaults != null) {
            # Profile defaults use mkDefault (priority 1000), while ordinary
            # Home Manager definitions use priority 100. Inherit explicit Darwin
            # values between them so they replace fallbacks without preventing a
            # deliberate Home Manager override.
            obsidian.vaults = lib.mkOverride 900 vaults;
          };
      };
    }
  );
}
