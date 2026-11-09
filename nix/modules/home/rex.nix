{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.rex;
  theme = import ../../lib/theme.nix;
  terminalColors = import ../../lib/terminal-colors.nix;
  programActivityStatusPreferences = builtins.toJSON {
    working = {
      sound = "loading";
      showsNotification = true;
      isEnabled = true;
      showsInTabs = true;
      badgesDockIcon = false;
      playsSound = false;
    };
  };

  hexByte = value: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString value));
  rgb = red: green: blue: "#${hexByte red}${hexByte green}${hexByte blue}";
  xtermLevels = [0 95 135 175 215 255];
  xtermExtendedPalette =
    lib.concatMap (
      red: lib.concatMap (green: map (blue: rgb red green blue) xtermLevels) xtermLevels
    )
    xtermLevels
    ++ map (index: let value = 8 + 10 * index; in rgb value value value) (lib.range 0 23);
  extendedPaletteLines = lib.imap0 (offset: color: "palette = ${toString (offset + 16)}=${color}") xtermExtendedPalette;
  mkRexTheme = variant: let
    terminal = theme.terminal variant;
    paletteLines = lib.imap0 (index: color: "palette = ${toString index}=${color}") terminal.ansi;
  in
    pkgs.writeText "rex-${variant}" (
      lib.concatStringsSep "\n" (
        paletteLines
        ++ extendedPaletteLines
        ++ [
          "background = ${terminal.background}"
          "foreground = ${terminal.foreground}"
          "cursor-color = ${terminal.cursor}"
          "cursor-text = ${terminal.cursorText}"
          "selection-background = ${terminal.selectionBackground}"
          "selection-foreground = ${terminal.selectionForeground}"
        ]
      )
      + "\n"
    );
  rexRosePineTheme = mkRexTheme "rose-pine";
  rexRosePineMoonTheme = mkRexTheme "rose-pine-moon";
  rexRosePineDawnTheme = mkRexTheme "rose-pine-dawn";
  rexDarkThemeName =
    if config.dotfiles.theme.darkVariant == "rose-pine-moon"
    then "Rose Pine Moon"
    else "Rose Pine";
  rexOtherDarkThemeName =
    if config.dotfiles.theme.darkVariant == "rose-pine-moon"
    then "Rose Pine"
    else "Rose Pine Moon";
  selectRexFzfColors = ''
    export DOTFILES_FZF_COLORS=${lib.escapeShellArg terminalColors.fzf}
  '';

  managedLazygit = config.programs.lazygit.package;
  managedNeovim = config.programs.neovim.finalPackage;
  rexPicker = pkgs.rex-picker;
  rexBundledCli = cfg.bundledCliPath;
  rexConfigSource =
    pkgs.runCommand "dotfiles-rex-config" {
      rexCapture = lib.getExe rexCli;
      scrollbackEditor = lib.getExe managedNeovim;
    } ''
      cp -R ${../../../rex} "$out"
      chmod -R u+w "$out"
      substituteInPlace "$out/init.lua" \
        --replace-fail '@rex_capture@' "$rexCapture" \
        --replace-fail '@scrollback_editor@' "$scrollbackEditor" \
        --replace-fail \
          'local password_picker_enabled = false' \
          'local password_picker_enabled = ${
        if cfg.passwordPicker.enable
        then "true"
        else "false"
      }'
    '';

  rexHistoryPicker = pkgs.writeShellApplication {
    name = "rex-history-picker";
    runtimeInputs = [pkgs.coreutils pkgs.fzf pkgs.nushell managedNeovim];
    text = ''
      export REX_BIN_PATH=${lib.escapeShellArg rexBundledCli}
      export FZF_BIN_PATH=${lib.escapeShellArg (lib.getExe pkgs.fzf)}
      export EDITOR=${lib.escapeShellArg (lib.getExe managedNeovim)}
      ${selectRexFzfColors}
      exec ${lib.getExe pkgs.nushell} --no-config-file ${../../../bin/rex/history-picker.nu} "$@"
    '';
  };
  rexCli = pkgs.writeShellApplication {
    name = "rex";
    text = ''
      rex=${lib.escapeShellArg rexBundledCli}
      if [[ ! -x "$rex" ]]; then
        echo "rex: bundled CLI is not installed at $rex" >&2
        exit 127
      fi
      exec "$rex" "$@"
    '';
  };
  rexLazygit = pkgs.writeShellApplication {
    name = "rex-lazygit";
    runtimeInputs = [pkgs.git managedLazygit];
    text = builtins.readFile ../../../bin/rex/lazygit;
  };
  rexLabelWindow = pkgs.writeShellApplication {
    name = "rex-label-window";
    runtimeInputs = [pkgs.coreutils pkgs.gawk pkgs.git pkgs.jq];
    text = builtins.readFile ../../../bin/rex/label-window;
  };
  rexNushell = pkgs.writeShellApplication {
    name = "rex-nushell";
    text = ''
      if [[ "$PWD" == "$HOME" && -d "$HOME/dev" ]]; then
        cd "$HOME/dev"
      fi
      exec ${lib.getExe pkgs.nushell} "$@"
    '';
  };
  rexDrawerFollowerSource = pkgs.runCommand "rex-drawer-follower-source" {} ''
    mkdir -p "$out/lib"
    cp ${../../../rex/follow-terminal-drawer.lua} "$out/follow-terminal-drawer.lua"
    cp ${../../../rex/lib/common.lua} "$out/lib/common.lua"
  '';
  rexDrawerFollowerLua = "${rexDrawerFollowerSource}/follow-terminal-drawer.lua";
  rexDrawerFollower = pkgs.writeShellApplication {
    name = "rex-drawer-follower";
    text = ''
      rex=${lib.escapeShellArg rexBundledCli}
      if [[ ! -x "$rex" ]]; then
        echo "rex-drawer-follower: bundled CLI is not installed at $rex" >&2
        exit 127
      fi

      unset GH_TOKEN GITHUB_TOKEN HOMEBREW_GITHUB_API_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN

      exec "$rex" --autostart=false "do" ${lib.escapeShellArg "${rexDrawerFollowerLua}"} --all --fail-fast
    '';
  };
in {
  options.dotfiles.rex = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      description = "Whether to configure the Rex terminal workflow";
    };

    bundledCliPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";
      description = "Version-matched CLI bundled with Rex.app";
    };

    drawerFollowEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether a visible floating terminal drawer follows the active Rex tab";
    };

    passwordPicker.enable = lib.mkEnableOption "the personal pass-backed Rex password picker";

    finalConfigSource = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = "Profile-specific store-managed Rex configuration source";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.isDarwin;
          message = "dotfiles.rex.enable is supported only on Darwin";
        }
      ];

      dotfiles = {
        rex.finalConfigSource = rexConfigSource;
        pi.skills = lib.mkAfter ["rex"];
      };

      home = {
        packages = [rexCli];
        file = {
          ".local/bin/rex-picker".source = lib.getExe rexPicker;
          ".local/bin/rex-gh-dash".source = lib.getExe pkgs.gh-dash;
          ".local/bin/rex-history-picker".source = lib.getExe rexHistoryPicker;
          ".local/bin/rex-lazygit".source = lib.getExe rexLazygit;
          ".local/bin/rex-label-window".source = lib.getExe rexLabelWindow;
          ".pi/agent/extensions/rex-model-picker.ts".source =
            ../../../agents/extensions/rex-model-picker.ts;
          ".pi/agent/extensions/rex-tab-label.ts".source =
            ../../../agents/extensions/rex-tab-label.ts;
        };
      };

      xdg.configFile = {
        "rex/init.lua" = {
          force = true;
          source = "${rexConfigSource}/init.lua";
        };
        "rex/lib/common.lua".source = "${rexConfigSource}/lib/common.lua";
        "rex/modules/navigation.lua".source = "${rexConfigSource}/modules/navigation.lua";
        "rex/modules/drawer.lua".source = "${rexConfigSource}/modules/drawer.lua";
        "rex/modules/drawer_state.lua".source = "${rexConfigSource}/modules/drawer_state.lua";
        "rex/modules/geometry.lua".source = "${rexConfigSource}/modules/geometry.lua";
        "rex/modules/pickers.lua".source = "${rexConfigSource}/modules/pickers.lua";
        "rex/modules/bindings.lua".source = "${rexConfigSource}/modules/bindings.lua";
        "rex/theme-policy.lua".text = ''
          return {
            dark_theme = os.getenv("HOME") .. "/.config/rex/themes/${rexDarkThemeName}",
          }
        '';
        "rex/themes/Rose Pine".source = rexRosePineTheme;
        "rex/themes/Rose Pine Moon".source = rexRosePineMoonTheme;
        "rex/themes/Rose Pine Dawn".source = rexRosePineDawnTheme;
      };

      programs.nushell.extraConfig = lib.mkAfter (builtins.readFile ./nushell/rex.nu);
      programs.ssh.includes = ["${config.xdg.configHome}/rex/ssh_config"];

      targets.darwin.defaults."com.superlogical.rex"."Workspace.terminalStartupCommand" =
        lib.getExe rexNushell;

      launchd.agents.rex-drawer-follower = lib.mkIf cfg.drawerFollowEnable {
        enable = true;
        restartTriggers = [rexDrawerFollower rexDrawerFollowerSource];
        config = {
          ProgramArguments = [(lib.getExe rexDrawerFollower)];
          RunAtLoad = true;
          KeepAlive.PathState."${config.home.homeDirectory}/Library/Application Support/rex/server.sock" = true;
          ProcessType = "Background";
          ThrottleInterval = 10;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/rex-drawer-follower.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/rex-drawer-follower.log";
        };
      };
    }
    {
      home.activation = {
        manageRexClient = lib.hm.dag.entryAfter ["linkGeneration"] ''
          (
          rex=${lib.escapeShellArg rexBundledCli}
          ssh_config=${lib.escapeShellArg "${config.home.homeDirectory}/.ssh/config"}
          preference_domain=com.superlogical.rex
          program_activity_status_preferences=${lib.escapeShellArg programActivityStatusPreferences}
          rose_pine_themes=(
            ${lib.escapeShellArg "${config.xdg.configHome}/rex/themes/${rexOtherDarkThemeName}"}
            ${lib.escapeShellArg "${config.xdg.configHome}/rex/themes/Rose Pine Dawn"}
            ${lib.escapeShellArg "${config.xdg.configHome}/rex/themes/${rexDarkThemeName}"}
          )

          if [ -n "''${DRY_RUN_CMD:-}" ]; then
            echo "Would remove the Rex tailnet-member access override"
            echo "Would set the Rex per-status program activity policy"
          else
            /usr/bin/defaults delete "$preference_domain" rex.server.tailnet-allow-tailnet-members >/dev/null 2>&1 || true
            program_activity_status_preferences_hex="$(
              printf '%s' "$program_activity_status_preferences" | /usr/bin/xxd -p -c 4096
            )"
            /usr/bin/defaults write "$preference_domain" Workspace.programActivityStatusPreferences \
              -data "$program_activity_status_preferences_hex"
          fi

          if [ ! -x "$rex" ]; then
            echo "Skipping Rex client setup: bundled CLI is not installed" >&2
          elif [ ! -L "$ssh_config" ]; then
            echo "Refusing Rex client setup without the Home Manager SSH config symlink: $ssh_config" >&2
            exit 1
          elif [ -n "''${DRY_RUN_CMD:-}" ]; then
            "$rex" terminfo setup --dry-run --json
            echo "Would reload Rex config when a local server is running"
            echo "Would import the managed Rosé Pine themes when a unique app client is connected"
          else
            if ! terminfo_output="$("$rex" terminfo setup --json)"; then
              printf '%s\n' "$terminfo_output" >&2
              exit 1
            fi

            if ! "$rex" --autostart=false config reload >/dev/null 2>&1; then
              echo "Skipping Rex config reload: no available local server" >&2
            else
              theme_import_failed=false
              for theme_path in "''${rose_pine_themes[@]}"; do
                if ! "$rex" --autostart=false do client.theme.import path="$theme_path" >/dev/null 2>&1; then
                  theme_import_failed=true
                  break
                fi
              done
              if [ "$theme_import_failed" = true ]; then
                echo "Skipping remaining Rex theme imports: no unique available app client" >&2
              fi
            fi
          fi
            )
        '';
      };
    }
  ]);
}
