{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.homebrew;
  primaryUser = config.system.primaryUser;
  onePasswordSafariAppId = "1569813296";
  onePasswordSafariApp = "/Applications/1Password for Safari.app";
  orcaSlicerCask = "orcaslicer@nightly";
  orcaSlicerBaseCask = builtins.head (lib.splitString "@" orcaSlicerCask);
  commonCasks = [
    "alfred"
    "claude"
    "obsidian"
  ];
  applicationCasks = [
    "bartender"
    "tailscale-app"
    "discord"
    "libation"
    {
      name = "navigator";
      greedy = true;
    }
    "raspberry-pi-imager"
    {
      name = "1password";
      greedy = true;
    }
  ];
  printingCasks = [
    orcaSlicerCask
    "bambu-studio"
  ];
in
{
  options.dotfiles = {
    homebrew = {
      applications.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.profile.name == "personal";
        description = "Whether to install the reviewed personal Homebrew application inventory";
      };
      printing.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.profile.name == "personal";
        description = "Whether to install personal 3D-printing applications and editor support";
      };
    };
    openlogi.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.profile.name == "personal";
      description = "Whether Homebrew installs the personal OpenLogi app and agent";
    };
    masApps.enable = lib.mkEnableOption "the reviewed personal Mac App Store inventory";
  };

  config = {
    homebrew = {
      enable = true;
      enableZshIntegration = true;
      brews = [ ];
      casks =
        commonCasks
        ++ lib.optionals cfg.applications.enable applicationCasks
        ++ lib.optionals cfg.printing.enable printingCasks
        ++ lib.optional config.dotfiles.openlogi.enable "openlogi";
      masApps = lib.mkIf config.dotfiles.masApps.enable {
        "Obsidian Web Clipper" = 6720708363;
        "TestFlight" = 899247664;
      };
      onActivation = {
        autoUpdate = true;
        upgrade = true;
        cleanup = "uninstall";
        # Set PATH after sudo so Homebrew Bundle can find the mas executable.
        extraEnv.PATH = "${config.homebrew.prefix}/bin:${lib.makeBinPath [ pkgs.mas ]}:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };

    dotfiles.yabai.applicationRules = lib.mkMerge [
      (lib.mkIf (cfg.applications.enable && config.dotfiles.yabai.fixedSpaceTargets) {
        discord = {
          match.app.pattern = "Discord";
          effects = {
            space.index = 1;
            follow = true;
          };
        };
      })
      (lib.mkIf (cfg.printing.enable && config.dotfiles.yabai.fixedSpaceTargets) {
        orcaslicer = {
          match.app.pattern = "OrcaSlicer";
          effects = {
            space.index = 5;
            follow = true;
          };
        };
      })
    ];

    home-manager.users.${primaryUser} = lib.mkIf cfg.printing.enable {
      programs.neovim = {
        extraPackages = [ pkgs.openscad-lsp ];
        plugins = [ pkgs.vimPlugins.vim-openscad ];
      };
    };

    system.activationScripts.mas.text = ''
      if [ ! -d ${lib.escapeShellArg onePasswordSafariApp} ]; then
        echo >&2 "installing 1Password for Safari..."
        primary_uid="$(/usr/bin/id -u -- ${lib.escapeShellArg primaryUser})"
        if ! /bin/launchctl asuser "$primary_uid" \
          /usr/bin/sudo --user=${lib.escapeShellArg primaryUser} --set-home -- \
          ${lib.getExe pkgs.mas} get ${onePasswordSafariAppId}; then
          echo >&2 "warning: could not install 1Password for Safari automatically"
          echo >&2 "Install it once from https://apps.apple.com/app/id${onePasswordSafariAppId}, then rebuild again."
        fi
      fi
    '';

    system.activationScripts.preActivation.text = lib.mkIf cfg.printing.enable ''
      stable_cask_receipt=${lib.escapeShellArg "${config.homebrew.prefix}/Caskroom/${orcaSlicerBaseCask}"}
      configured_cask_receipt=${lib.escapeShellArg "${config.homebrew.prefix}/Caskroom/${orcaSlicerCask}"}

      if [ -e "$stable_cask_receipt" ] || [ -L "$stable_cask_receipt" ]; then
        sudo \
          --user=${lib.escapeShellArg config.homebrew.user} \
          --set-home \
          ${config.homebrew.prefix}/bin/brew uninstall --cask ${lib.escapeShellArg orcaSlicerBaseCask} >/dev/null 2>&1 || true
      fi

      if [ ! -e /Applications/OrcaSlicer.app ] \
        && { [ -e "$configured_cask_receipt" ] || [ -L "$configured_cask_receipt" ]; }; then
        sudo \
          --user=${lib.escapeShellArg config.homebrew.user} \
          --set-home \
          ${config.homebrew.prefix}/bin/brew uninstall --cask ${lib.escapeShellArg orcaSlicerCask} >/dev/null 2>&1 || true
      fi
    '';
  };
}
