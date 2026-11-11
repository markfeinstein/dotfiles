{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.homebrew;
  primaryUser = config.system.primaryUser;
  orcaSlicerCask = "orcaslicer@nightly";
  orcaSlicerBaseCask = builtins.head (lib.splitString "@" orcaSlicerCask);
  commonCasks = ["alfred"];
  applicationCasks = [
    "bartender"
    "tailscale-app"
    "discord"
    "libation"
    {
      name = "navigator";
      greedy = true;
    }
    "obsidian"
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
in {
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
      brews = [];
      casks =
        commonCasks
        ++ lib.optionals cfg.applications.enable applicationCasks
        ++ lib.optionals cfg.printing.enable printingCasks
        ++ lib.optional config.dotfiles.openlogi.enable "openlogi";
      masApps = lib.mkIf config.dotfiles.masApps.enable {
        "1Password for Safari" = 1569813296;
        "Obsidian Web Clipper" = 6720708363;
        "TestFlight" = 899247664;
      };
      onActivation = {
        autoUpdate = true;
        upgrade = true;
        cleanup = "uninstall";
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
        extraPackages = [pkgs.openscad-lsp];
        plugins = [pkgs.vimPlugins.vim-openscad];
      };
    };

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
