{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.rex;
  primaryUser = config.system.primaryUser;
  rexApp = pkgs.rex-app;
  installRexApp = pkgs.writeShellApplication {
    name = "install-rex-app";
    text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./scripts/install-rex-app);
  };
  installRexAppArgs = lib.escapeShellArgs [
    "--source-app"
    "${rexApp}/Applications/${rexApp.appName}"
    "--primary-user"
    primaryUser
    "--bundle-identifier"
    rexApp.bundleIdentifier
    "--team-identifier"
    rexApp.teamIdentifier
  ];
in {
  options.dotfiles.rex = {
    installApp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install the signed Rex application in /Applications";
    };

    tailnetEnable = lib.mkOption {
      type = lib.types.bool;
      default = config.profile.name == "personal";
      description = "Whether Rex serves its bundled server on the authenticated tailnet";
    };
  };

  config = {
    dotfiles.yabai.applicationRules =
      {
        rex-settings = {
          match = {
            app.pattern = "Rex Beta";
            title.pattern = "^Settings - ";
          };
          effects.manage = false;
        };
      }
      // lib.optionalAttrs config.dotfiles.yabai.fixedSpaceTargets {
        rex = {
          match.app.pattern = "Rex Beta";
          effects = {
            space.index = 3;
            follow = true;
          };
        };
      };

    fonts.packages = [pkgs.nerd-fonts.symbols-only];

    system.activationScripts.preActivation.text = lib.mkIf cfg.installApp (lib.mkBefore ''
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would install the signed Rex application in /Applications"
      else
        rex_app_install_result="$(${lib.getExe installRexApp} ${installRexAppArgs})"
        case "$rex_app_install_result" in
          no-op|changed) ;;
          *) echo "unexpected Rex application installation result: $rex_app_install_result" >&2; exit 1 ;;
        esac
      fi
    '');

    home-manager.users.${primaryUser}.targets.darwin.defaults."com.superlogical.rex" = {
      "RexAppUpdateChannel" = "snapshot";
      "RexAppUpdateAutomation" = "install";
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      SUScheduledCheckInterval = 3600.0;

      "Workspace.appearance" = "system";
      "Workspace.interfaceStyle" = "useTheme";
      "Workspace.tabStyle" = "vertical";
      "Workspace.sidebarPosition" = "left";
      "Workspace.appIconVisibility" = "dockAndMenuBar";
      "Workspace.showsWindowOnLaunch" = true;
      "Workspace.inactivePaneFadeMode" = "both";
      "Workspace.usesPaneGlass" = true;
      "Workspace.usesStandardInactiveWindowPaneStyles" = true;
      "Workspace.paneDensity" = "comfortable";
      "Workspace.showsActivePaneBorder" = true;
      "Workspace.showsPaneHeaders" = true;
      "Workspace.shellIconTheme" = "default";
      "Workspace.tabIconCount" = 3;
      "Workspace.tabIconTintMode" = "off";
      "Workspace.usesGestures" = true;

      "Workspace.terminalFontName" = "JetBrains Mono";
      "Workspace.terminalFontPointSize" = 14;
      "Workspace.terminalPaddingY" = 8.0;
      "Workspace.terminalFallbackFontNames" = ["Symbols Nerd Font Mono"];
      "Workspace.terminalAllowsLigatures" = true;
      "Workspace.terminalFontSmoothing" = false;
      "Workspace.terminalSmoothScrolling" = true;
      "Workspace.smoothResizeEnabled" = true;
      "Workspace.terminalCursorStyle" = "block";
      "Workspace.terminalCursorStyleForced" = false;
      "Workspace.terminalCursorBlinkIntervalMilliseconds" = 500;
      "Workspace.terminalCursorBlinkUsesCustomInterval" = true;
      "Workspace.terminalOptionKeyBehavior" = "automatic";

      "Workspace.balancesSplitsOnCreation" = true;
      "Workspace.focusFollowsMouse" = true;
      "Workspace.terminalCopyOnSelect" = true;
      "Workspace.terminalCopyAnimation" = true;
      "Workspace.terminalImproveTextContrast" = false;
      "Workspace.terminalUseThemePalette" = false;
      "Workspace.terminalUsesDisplayP3" = false;

      "Workspace.notificationPosition" = "top-right";
      "Workspace.sidebarShowsActivity" = false;
      "Workspace.experiments.groupsActivityByPriority" = true;
      "Workspace.activityGrouping" = "priority";
      "Workspace.showsIdleProgramsInActivity" = true;
      "Workspace.showsProcessesInActivity" = true;
      "Workspace.showsProgramStatusInTabs" = true;
      "Workspace.showsProgramActivityNotifications" = true;
      "Workspace.showsProgramActivityDockBadge" = true;
      "Workspace.playsProgramActivitySounds" = true;

      "rex.client.remoteControl" = true;
      "rex.developer-mode-enabled" = true;
      "rex.server.tailnet-enabled" = cfg.tailnetEnable;
      "rex.server.automatic-restart-enabled" = true;
      "rex.server.block-plugin-reload-enabled" = false;
      "rex.server.run-mode" = "bundled";
      "rex.server.web-client-origin-patterns" = ["https://rex.superlogical.com"];
      "rex.agents.names-sessions" = true;
    };
  };
}
