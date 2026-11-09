{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.rex;
in {
  options.dotfiles.rex.tailnetEnable = lib.mkOption {
    type = lib.types.bool;
    default = config.profile.name == "personal";
    description = "Whether Rex serves its bundled server on the authenticated tailnet";
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

    home-manager.users.${config.system.primaryUser}.targets.darwin.defaults."com.superlogical.rex" = {
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
