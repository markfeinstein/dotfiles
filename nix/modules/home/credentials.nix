{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.credentials;
  absolutePath = description:
    lib.mkOption {
      type = lib.types.str;
      inherit description;
    };
in {
  options.dotfiles.credentials = {
    enable = lib.mkEnableOption "personal pass, GPG, and non-secret credential environment";

    passwordStoreDirectory =
      absolutePath "Directory containing the personal pass store"
      // {
        default = "${config.xdg.dataHome}/password-store";
      };

    localSshConfigPath =
      absolutePath "Optional machine-local OpenSSH include"
      // {
        default = "${config.home.homeDirectory}/.ssh/config.local";
      };

    sopsAgeKeyFile =
      absolutePath "Expected local SOPS age-key file"
      // {
        default = "${config.xdg.configHome}/sops/age/keys.txt";
      };

    biometricUnlock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the 1Password CLI may use biometric unlock integration";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (path: lib.hasPrefix "/" path) [
          cfg.passwordStoreDirectory
          cfg.localSshConfigPath
          cfg.sopsAgeKeyFile
        ];
        message = "dotfiles.credentials paths must be absolute";
      }
    ];

    programs.ssh.includes = [cfg.localSshConfigPath];

    home = {
      packages = [
        pkgs.gnupg
        pkgs.pass
      ];

      sessionVariables =
        {
          PASSWORD_STORE_DIR = cfg.passwordStoreDirectory;
          SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
        }
        // lib.optionalAttrs cfg.biometricUnlock {
          OP_BIOMETRIC_UNLOCK_ENABLED = "true";
        };

      activation.prepareCredentialPaths = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        store=${lib.escapeShellArg cfg.passwordStoreDirectory}
        compatibility="$HOME/.password-store"

        if [ -L "$store" ] || { [ -e "$store" ] && [ ! -d "$store" ]; }; then
          echo "Refusing unsafe password store path: $store" >&2
          exit 1
        fi
        if [ -e "$store" ] && [ ! -O "$store" ]; then
          echo "Refusing password store not owned by the current user: $store" >&2
          exit 1
        fi
        if [ -e "$compatibility" ] && [ ! -L "$compatibility" ]; then
          echo "Refusing to replace existing non-symlink $compatibility" >&2
          exit 1
        fi

        $DRY_RUN_CMD install -d -m 0700 "$store"
      '';

      file.".password-store".source =
        config.lib.file.mkOutOfStoreSymlink cfg.passwordStoreDirectory;
    };
  };
}
