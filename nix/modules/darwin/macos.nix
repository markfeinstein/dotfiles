{
  config,
  lib,
  pkgs,
  ...
}: let
  primaryUser = config.system.primaryUser;
  primaryHome = config.profile.user.homeDirectory;
  nativeTrackpadGestureDefaults = {
    TrackpadThreeFingerHorizSwipeGesture = 2;
    TrackpadThreeFingerVertSwipeGesture = 2;
  };
  externalTrackpadDefaults =
    {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadCornerSecondaryClick = 0;
      TrackpadTwoFingerTapGesture = 1;
    }
    // nativeTrackpadGestureDefaults;
  disabledMacosSymbolicHotKeys = config.dotfiles.macosSymbolicHotKeys.disabled;
  enabledMacosSymbolicHotKeys = config.dotfiles.macosSymbolicHotKeys.enabled;
  structuredDockDefaults = builtins.removeAttrs config.system.defaults.dock ["expose-group-by-app"];
  managedDockDefaults = config.system.defaults.CustomUserPreferences."com.apple.dock";
  managedDockDefaultsJson = pkgs.writeText "managed-dock-defaults.json" (builtins.toJSON managedDockDefaults);
  dockPreferencesMatch = pkgs.writeShellScript "dock-preferences-match" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/dock-preferences-match.py} "$@"
  '';
  disabledMacosSymbolicHotKeysArgs = lib.concatMapStringsSep " " toString disabledMacosSymbolicHotKeys;
  enabledMacosSymbolicHotKeysArgs = lib.concatMapStringsSep " " toString enabledMacosSymbolicHotKeys;
  disabledMacosSymbolicHotKeysC = lib.concatMapStringsSep ", " toString (disabledMacosSymbolicHotKeys ++ [(0 - 1)]);
  enabledMacosSymbolicHotKeysC = lib.concatMapStringsSep ", " toString (enabledMacosSymbolicHotKeys ++ [(0 - 1)]);

  configureMacosSymbolicHotKeys = pkgs.runCommand "configure-macos-symbolic-hotkeys" {} ''
    mkdir -p $out/bin
    ${pkgs.clang}/bin/clang -framework Carbon -x c -o $out/bin/configure-macos-symbolic-hotkeys - <<'EOF'
    #include <Carbon/Carbon.h>

    extern bool CGSIsSymbolicHotKeyEnabled(int hotKey);
    extern CGError CGSSetSymbolicHotKeyEnabled(int hotKey, bool isEnabled);

    static int configure(const int *hotKeys, bool enabled) {
      int failed = 0;
      for (unsigned long i = 0; hotKeys[i] != -1; i++) {
        if (CGSIsSymbolicHotKeyEnabled(hotKeys[i]) != enabled) {
          failed |= CGSSetSymbolicHotKeyEnabled(hotKeys[i], enabled) != kCGErrorSuccess;
        }
        failed |= CGSIsSymbolicHotKeyEnabled(hotKeys[i]) != enabled;
      }
      return failed;
    }

    int main(void) {
      const int disabledHotKeys[] = { ${disabledMacosSymbolicHotKeysC} };
      const int enabledHotKeys[] = { ${enabledMacosSymbolicHotKeysC} };
      return configure(disabledHotKeys, false) | configure(enabledHotKeys, true);
    }
    EOF
  '';
  activationHelpers = import ./activation-helpers.nix {inherit config;};
in {
  options.dotfiles.macosSymbolicHotKeys = {
    disabled = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [];
      description = "macOS symbolic hotkey IDs disabled by the active configuration";
    };
    enabled = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [];
      description = "macOS symbolic hotkey IDs explicitly enabled by the active configuration";
    };
  };

  config = {
    assertions = [
      {
        assertion = primaryUser != "";
        message = "macOS policy requires system.primaryUser";
      }
      {
        assertion = lib.intersectLists disabledMacosSymbolicHotKeys enabledMacosSymbolicHotKeys == [];
        message = "dotfiles.macosSymbolicHotKeys.enabled and .disabled must not overlap";
      }
      {
        assertion = builtins.all (value: value == null) (builtins.attrValues structuredDockDefaults);
        message = "Dock preferences must use CustomUserPreferences so unchanged activation keeps Dock running";
      }
    ];

    environment.enableAllTerminfo = false;

    home-manager.backupCommand = pkgs.writeShellScript "home-manager-backup" ''
      set -e
      target=$1
      backup=$target.backup
      if [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
        mv "$target" "$backup"
        exit 0
      fi
      n=1
      while :; do
        candidate=$backup.$n
        if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
          mv "$target" "$candidate"
          exit 0
        fi
        n=$((n + 1))
      done
    '';

    launchd.daemons.maxfiles = {
      command = "/bin/launchctl limit maxfiles 8192 unlimited";
      serviceConfig = {
        RunAtLoad = true;
        LaunchOnlyOnce = true;
        SoftResourceLimits.NumberOfFiles = 8192;
        HardResourceLimits.NumberOfFiles = 1048576;
      };
    };

    dotfiles.macosSymbolicHotKeys = {
      disabled = [
        60
        61
        64
        65
        79
        80
        81
        82
        118
        119
        120
        121
        122
        123
        124
        125
        126
      ];
      enabled = [
        32
        33
      ];
    };

    system = {
      keyboard = {
        enableKeyMapping = true;
        remapCapsLockToEscape = true;
      };

      defaults = {
        trackpad = {
          TrackpadRightClick = true;
          TrackpadCornerSecondaryClick = 0;
          Clicking = true;
          TrackpadPinch = true;
          inherit (nativeTrackpadGestureDefaults) TrackpadThreeFingerHorizSwipeGesture;
        };
        NSGlobalDomain = {
          "com.apple.trackpad.enableSecondaryClick" = true;
          NSAutomaticWindowAnimationsEnabled = false;
          NSWindowResizeTime = 0.001;
          NSScrollAnimationEnabled = false;
          AppleShowAllExtensions = false;
          InitialKeyRepeat = 15;
          KeyRepeat = 2;
          AppleKeyboardUIMode = 3;
          AppleShowScrollBars = "Always";
        };
        CustomUserPreferences = {
          "com.apple.AppleMultitouchTrackpad" = externalTrackpadDefaults;
          "com.apple.driver.AppleBluetoothMultitouch.trackpad" = externalTrackpadDefaults;
          "com.apple.dock" = {
            tilesize = 36;
            orientation = "left";
            autohide = true;
            "autohide-delay" = 0.0;
            "autohide-time-modifier" = 0.0;
            launchanim = false;
            "expose-animation-duration" = 0.1;
            mineffect = "scale";
            "show-recents" = false;
            "show-process-indicators" = true;
            "mru-spaces" = false;
            stackViewStyle = "list";
            showDesktopGestureEnabled = true;
            "persistent-apps" = [
              {
                "tile-data"."file-data" = {
                  _CFURLString = "/Applications/Safari.app";
                  _CFURLStringType = 0;
                };
              }
            ];
            "persistent-others" = [
              {
                "tile-data" = {
                  "file-data" = {
                    _CFURLString = "file://${primaryHome}/Downloads";
                    _CFURLStringType = 15;
                  };
                  arrangement = 2;
                  displayas = 1;
                  showas = 3;
                };
                "tile-type" = "directory-tile";
              }
            ];
          };
        };
        finder = {
          ShowStatusBar = true;
          ShowPathbar = true;
          ShowHardDrivesOnDesktop = true;
          ShowExternalHardDrivesOnDesktop = true;
          AppleShowAllExtensions = false;
          FXPreferredViewStyle = "Nlsv";
          _FXSortFoldersFirst = true;
          FXEnableExtensionChangeWarning = false;
          FXDefaultSearchScope = "SCcf";
          QuitMenuItem = true;
        };
        spaces.spans-displays = false;
        controlcenter.BatteryShowPercentage = true;
        screensaver = {
          askForPassword = true;
          askForPasswordDelay = 900;
        };
        screencapture = {
          location = "${primaryHome}/Screenshots";
          type = "png";
          disable-shadow = true;
          show-thumbnail = false;
        };
        WindowManager = {
          EnableStandardClickToShowDesktop = false;
          EnableTilingByEdgeDrag = false;
          EnableTopTilingByEdgeDrag = false;
          EnableTilingOptionAccelerator = false;
          EnableTiledWindowMargins = false;
        };
      };

      activationScripts = {
        userDefaults.text = lib.mkMerge [
          (lib.mkBefore ''
            dotfiles_dock_restart_needed=0
            if ! launchctl asuser "$(id -u -- ${lib.escapeShellArg primaryUser})" \
              sudo --user=${lib.escapeShellArg primaryUser} -- \
              ${dockPreferencesMatch} ${managedDockDefaultsJson}; then
              dotfiles_dock_restart_needed=1
            fi
          '')
          (lib.mkAfter ''
            if [ "$dotfiles_dock_restart_needed" -eq 1 ]; then
              echo >&2 "managed Dock preferences changed; restarting Dock..."
              killall -qu ${lib.escapeShellArg primaryUser} Dock || true
            else
              echo >&2 "managed Dock preferences unchanged; keeping Dock running"
            fi
          '')
        ];
        postActivation.text = lib.mkAfter ''
          mkdir -p ${lib.escapeShellArg "${primaryHome}/Screenshots"}
          chown ${lib.escapeShellArg primaryUser} ${lib.escapeShellArg "${primaryHome}/Screenshots"}

          /usr/bin/pmset -b displaysleep 10
          /usr/bin/pmset -c displaysleep 30

          ${activationHelpers.configureMacosSymbolicHotKeys {inherit disabledMacosSymbolicHotKeysArgs enabledMacosSymbolicHotKeysArgs;}}
          ${activationHelpers.disableSafariSidebarShortcut}
          ${activationHelpers.reloadPreferencesAndConfigureLiveHotKeys {inherit configureMacosSymbolicHotKeys;}}
        '';
      };
    };
  };
}
