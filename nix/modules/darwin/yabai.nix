{
  config,
  lib,
  yabaiInput,
  ...
}: let
  primaryUser = config.system.primaryUser;
  nightlyPin = builtins.fromJSON (builtins.readFile "${yabaiInput}/nix/nightly.json");
  nightlyAvailable = builtins.all (value: value != null) [
    (nightlyPin.tag or null)
    (nightlyPin.version or null)
    (nightlyPin.hash or null)
  ];
  unmanagedRule = label: pattern: {
    inherit label;
    match.app.pattern = pattern;
    effects.manage = false;
  };
  # Native target resolution is intentionally strict: every referenced Space
  # index must exist during startup and reload, or yabai rejects the generation.
  # Follow the assigned Space when opening an application from another Space.
  spaceRule = label: pattern: index: {
    inherit label;
    match.app.pattern = pattern;
    effects = {
      space.index = index;
      follow = true;
    };
  };
  applicationRules = lib.mapAttrsToList (label: rule: {inherit label;} // rule) config.dotfiles.yabai.applicationRules;

  rexApplication.bundle_id = "com.superlogical.rex";
  rexSettingsWindow.title_prefix = "Settings - ";
  consumeAction = action: [
    {
      disposition = "consume";
      inherit action;
    }
  ];
  consumeTransition = transition: [
    {
      disposition = "consume";
      inherit transition;
    }
  ];
  keyBinding = key: modifiers: action: {
    inherit key modifiers;
    cases = consumeAction action;
  };
  keyBindingNoRepeat = key: modifiers: action:
    (keyBinding key modifiers action)
    // {repeat = false;};
  keycodeBinding = keycode: modifiers: action: {
    inherit keycode modifiers;
    cases = consumeAction action;
  };
  transitionBinding = key: modifiers: transition: {
    inherit key modifiers;
    repeat = false;
    cases = consumeTransition transition;
  };
  keycodeTransitionBinding = keycode: modifiers: transition: {
    inherit keycode modifiers;
    repeat = false;
    cases = consumeTransition transition;
  };
  transitionActionBinding = key: modifiers: transition: action: {
    inherit key modifiers;
    repeat = false;
    cases = [
      {
        disposition = "consume";
        inherit transition action;
      }
    ];
  };
  focusAction = direction: robust: {
    type = "focus_window";
    inherit direction robust;
  };
  warpAction = direction: {
    type = "warp_window";
    inherit direction;
  };
  directionalKeys = [
    {
      key = "h";
      direction = "west";
    }
    {
      key = "j";
      direction = "south";
    }
    {
      key = "k";
      direction = "north";
    }
    {
      key = "l";
      direction = "east";
    }
  ];
  workspaceKeys = [
    {
      keycode = "0x12";
      index = 1;
    }
    {
      keycode = "0x13";
      index = 2;
    }
    {
      keycode = "0x14";
      index = 3;
    }
    {
      keycode = "0x15";
      index = 4;
    }
    {
      keycode = "0x17";
      index = 5;
    }
    {
      keycode = "0x16";
      index = 6;
    }
    {
      keycode = "0x1A";
      index = 7;
    }
    {
      keycode = "0x1C";
      index = 8;
    }
    {
      keycode = "0x19";
      index = 9;
    }
  ];
  # Rex terminal windows consume these chords internally, but Settings does
  # not. Match Settings first so it can leave through native robust focus.
  robustFocusCases = direction: [
    {
      application = rexApplication;
      window = rexSettingsWindow;
      disposition = "consume";
      action = focusAction direction true;
    }
    {
      application = rexApplication;
      disposition = "pass_through";
    }
    {
      disposition = "consume";
      action = focusAction direction true;
    }
  ];
  robustFocusBinding = key: direction: {
    inherit key;
    modifiers = ["ctrl"];
    cases = robustFocusCases direction;
  };
  defaultKeyboardBindings =
    [
      {
        key = "h";
        modifiers = ["cmd"];
        repeat = false;
        cases = [
          {
            application = rexApplication;
            disposition = "remap";
            action = {
              type = "synthesize_key";
              key = "h";
              modifiers = ["ctrl" "alt" "cmd"];
            };
          }
          {disposition = "consume_only";}
        ];
      }
    ]
    ++ map (item: robustFocusBinding item.key item.direction) directionalKeys
    ++ [
      {
        key = "backspace";
        modifiers = ["ctrl"];
        cases = robustFocusCases "west";
      }
    ]
    ++ map (item: keyBinding item.key ["alt"] (focusAction item.direction false)) directionalKeys
    ++ map (item: keyBinding item.key ["alt" "ctrl"] (warpAction item.direction)) directionalKeys
    ++ [
      (keyBindingNoRepeat "s" ["alt"] {type = "cycle_space_layout";})
      (keyBindingNoRepeat "r" ["alt"] {
        type = "rotate_space";
        degrees = 90;
      })
      (keyBindingNoRepeat "space" ["alt" "shift"] {type = "toggle_floating";})
      (keyBindingNoRepeat "f" ["alt"] {type = "toggle_zoom_fullscreen";})
      (keyBindingNoRepeat "f" ["alt" "ctrl"] {type = "toggle_zoom_fullscreen";})
      (keycodeBinding "0x1B" ["alt"] {
        type = "adaptive_resize";
        direction = "shrink";
      })
      (keycodeBinding "0x18" ["alt"] {
        type = "adaptive_resize";
        direction = "grow";
      })
      (keyBinding "left" ["ctrl"] {
        type = "focus_occupied_space";
        direction = "previous";
      })
      (keyBinding "right" ["ctrl"] {
        type = "focus_occupied_space";
        direction = "next";
      })
    ]
    ++ lib.concatMap (workspace: [
      (keycodeBinding workspace.keycode ["ctrl"] {
        type = "focus_space";
        inherit (workspace) index;
      })
      (keycodeBinding workspace.keycode ["alt" "ctrl"] [
        {
          type = "move_window_to_space";
          inherit (workspace) index;
        }
        {
          type = "focus_space";
          inherit (workspace) index;
        }
      ])
    ])
    workspaceKeys
    ++ [
      (transitionBinding "r" ["alt" "ctrl"] "resize")
      (keycodeTransitionBinding "0x29" ["alt" "shift"] "service")
    ];
  resizeModeBindings =
    map (item:
      keyBinding item.key [] {
        type = "adaptive_resize";
        inherit (item) direction;
      })
    directionalKeys
    ++ [
      (transitionBinding "return" [] "default")
      (transitionBinding "escape" [] "default")
    ];
  serviceModeBindings =
    [
      (keyBindingNoRepeat "escape" [] {type = "reload_configuration";})
      (transitionActionBinding "return" [] "default" {
        type = "restart_service";
        label = "com.asmvik.yabai";
      })
      (keyBindingNoRepeat "r" [] [
        {
          type = "set_space_layout";
          layout = "bsp";
        }
        {type = "balance_space";}
      ])
      (keyBindingNoRepeat "f" [] {type = "toggle_floating";})
      (keyBindingNoRepeat "backspace" [] {type = "close_other_windows";})
    ]
    ++ map (item: keyBinding item.key ["alt" "shift"] (warpAction item.direction)) directionalKeys;
  yabaiKeyboard = {
    enabled = true;
    bindings = defaultKeyboardBindings;
    modes = [
      {
        name = "resize";
        capture_unbound = true;
        bindings = resizeModeBindings;
      }
      {
        name = "service";
        capture_unbound = true;
        bindings = serviceModeBindings;
      }
    ];
  };

  yabaiNativeConfig = {
    version = 3;
    config = {
      layout = "bsp";
      single_window_width_ratio = 0.9;
      single_window_min_width = 1200;
      single_window_max_width = 2400;
      split_type = "auto";
      window_placement = "second_child";
      window_insertion_point = "focused";
      window_zoom_persist = true;
      direct_space_switch = true;
      skip_window_focus_animation = true;
      auto_balance = "on";
      window_origin_display = "focused";
      window_focus_fallback = "recent";
      display_arrangement_order = "horizontal";

      # Use the native AppKit menu instead of the expanded panel session.
      menubar = "on";
      menubar_interface = "menu";
      menubar_style = "automatic";
      menubar_space_filter = "occupied";

      window_animation_duration = 0.0;

      # Native active-window outline.
      active_window_highlight = true;
      active_window_highlight_color = 4288466904; # 0xff9ccfd8
      active_window_highlight_radius = 12.0;
      active_window_highlight_width = 3.0;

      insert_feedback_color = 4288466904;

      top_padding = 2;
      bottom_padding = 2;
      left_padding = 2;
      right_padding = 2;
      window_gap = 5;

      mouse_modifier = "alt";
      mouse_action1 = "move";
      mouse_action2 = "resize";
      mouse_drop_action = "swap";
      native_edge_resize = true;
      mouse_bsp_live_resize = false;

      focus_follows_mouse = "off";
      mouse_follows_focus = false;
    };
    # Fixed-index assignments are opt-in because profile outputs are not tied
    # to a machine's existing native Space count.
    spaces = lib.optionals config.dotfiles.yabai.fixedSpaceTargets [
      {
        match.index = 2;
        settings.split_ratio = 0.6;
        scaffold = [
          {pattern = "Mail";}
          {pattern = "Calendar";}
          {pattern = "Messages";}
        ];
      }
      {
        match.index = 9;
        settings = {
          layout = "accordion_horizontal";
          accordion_padding = 40;
        };
      }
    ];
    keyboard = yabaiKeyboard;
    rules =
      [
        (unmanagedRule "bambu-studio-float" "Bambu Studio")
        (unmanagedRule "system-settings" "System Settings")
        (unmanagedRule "finder" "Finder")
        (unmanagedRule "1password" "1Password")
        {
          label = "obsidian-settings";
          match = {
            app.pattern = "Obsidian";
            title.pattern = "^Settings - ";
          };
          effects.manage = false;
        }
        (unmanagedRule "calculator" "Calculator")
        (unmanagedRule "activity-monitor" "Activity Monitor")
        (unmanagedRule "archive-utility" "Archive Utility")
        (unmanagedRule "digital-color-meter" "Digital Color Meter")
        (unmanagedRule "font-book" "Font Book")
        (unmanagedRule "disk-utility" "Disk Utility")
        (unmanagedRule "keychain-access" "Keychain Access")
        (unmanagedRule "system-information" "System Information")
      ]
      ++ applicationRules
      ++ lib.optionals config.dotfiles.yabai.fixedSpaceTargets [
        (spaceRule "facetime" "FaceTime" 1)
        (spaceRule "teams" "Microsoft Teams" 1)
        (spaceRule "teams2" "Microsoft Teams.*" 1)
        (spaceRule "zoom" "zoom.us" 1)
        (spaceRule "outlook" "Microsoft Outlook" 2)
        (spaceRule "mail" "Mail" 2)
        (spaceRule "calendar" "Calendar" 2)
        (spaceRule "slack" "Slack" 2)
        (spaceRule "messages" "Messages" 2)
        (spaceRule "terminal" "Terminal" 3)
        (spaceRule "wezterm" "WezTerm" 3)
        (spaceRule "safari" "Safari" 4)
        (spaceRule "bambu-studio-space" "Bambu Studio" 5)
        (spaceRule "obsidian" "Obsidian" 9)
        (spaceRule "reminders" "Reminders" 9)
        (spaceRule "things" "Things" 9)
      ];
  };
  yabaiNativeConfigJson = builtins.toJSON yabaiNativeConfig;
in {
  options.dotfiles.yabai = {
    installSource = lib.mkOption {
      type = lib.types.enum [
        "nightly"
        "release"
      ];
      default =
        if nightlyAvailable
        then "nightly"
        else "release";
      description = ''
        Signed Yabai artifact channel. The default follows the latest verified
        nightly pinned by the Yabai input and falls back to the signed release
        until the first nightly is available.
      '';
    };

    fixedSpaceTargets = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable fixed Space 1-9 assignments only on machines with those native Spaces";
    };

    applicationRules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          match = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
          };
          effects = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
          };
        };
      });
      default = {};
      internal = true;
      description = "Native yabai rules contributed by modules that manage the matching applications.";
    };

    nativeConfigJson = lib.mkOption {
      type = lib.types.str;
      internal = true;
      default = "";
    };
  };

  config = {
    dotfiles.yabai.nativeConfigJson = yabaiNativeConfigJson;

    home-manager.users.${primaryUser} = {
      imports = [yabaiInput.homeManagerModules.yabai];

      programs.yabai = {
        enable = true;
        force = true;
        install.source = config.dotfiles.yabai.installSource;
        settings = yabaiNativeConfig;
      };
    };
  };
}
