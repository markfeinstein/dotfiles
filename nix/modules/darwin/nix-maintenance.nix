{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.nixMaintenance;
  nixBin = "/nix/var/nix/profiles/default/bin/nix";
  collectGarbage = "/nix/var/nix/profiles/default/bin/nix-collect-garbage";
  retention = "${toString cfg.retentionDays}d";
  lockDirectory = "/var/run/determinate-nix-maintenance.lock";

  maintenance = pkgs.writeShellApplication {
    name = "determinate-nix-maintenance";
    text = ''
      usage() {
        cat <<'HELP'
      Usage: determinate-nix-maintenance [--dry-run]

      Delete Nix profile generations older than the configured retention period,
      collect unreachable store objects, and optimise the remaining store.

      --dry-run  Print the exact privileged commands without running them
      --help     Show this help
      HELP
      }

      case "''${1:-}" in
        --dry-run)
          [[ $# -eq 1 ]] || { usage >&2; exit 64; }
          printf '%s\n' '${collectGarbage} --delete-older-than ${retention}'
          printf '%s\n' '${nixBin} store optimise'
          exit 0
          ;;
        --help|-h)
          [[ $# -eq 1 ]] || { usage >&2; exit 64; }
          usage
          exit 0
          ;;
        "")
          ;;
        *)
          usage >&2
          exit 64
          ;;
      esac

      [[ $# -eq 0 ]] || { usage >&2; exit 64; }
      [[ $(/usr/bin/id -u) -eq 0 ]] || {
        echo 'determinate-nix-maintenance must run as root' >&2
        exit 1
      }
      [[ -x ${collectGarbage} && -x ${nixBin} ]] || {
        echo 'Determinate Nix commands are unavailable in the default profile' >&2
        exit 1
      }

      if ! ${pkgs.coreutils}/bin/mkdir ${lockDirectory} 2>/dev/null; then
        echo 'Nix maintenance lock exists; inspect before removing it:' >&2
        echo '  ${lockDirectory}' >&2
        exit 75
      fi
      cleanup() {
        ${pkgs.coreutils}/bin/rmdir ${lockDirectory} 2>/dev/null || true
      }
      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM

      echo 'Deleting Nix profile generations older than ${retention}'
      ${collectGarbage} --delete-older-than ${retention}
      echo 'Optimising the Nix store'
      ${nixBin} store optimise
      echo 'Nix maintenance completed'
    '';
  };
in {
  options.dotfiles.nixMaintenance = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run bounded maintenance against the Determinate-owned Nix store.";
    };

    retentionDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Minimum age in days for profile generations removed by maintenance.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Generated Determinate Nix maintenance command.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.retentionDays >= 7;
        message = "dotfiles.nixMaintenance.retentionDays must be at least seven days";
      }
      {
        assertion = !config.nix.enable;
        message = "Determinate Nix maintenance requires nix.enable = false";
      }
    ];

    dotfiles.nixMaintenance.package = maintenance;
    environment.systemPackages = [maintenance];

    launchd.daemons.determinate-nix-maintenance.serviceConfig = {
      ProgramArguments = ["${maintenance}/bin/determinate-nix-maintenance"];
      StartCalendarInterval = {
        Weekday = 0;
        Hour = 2;
        Minute = 0;
      };
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/var/log/determinate-nix-maintenance.log";
      StandardErrorPath = "/var/log/determinate-nix-maintenance.log";
    };
  };
}
