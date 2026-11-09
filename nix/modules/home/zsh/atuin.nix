{lib, ...}: let
  terminalColors = import ../../../lib/terminal-colors.nix;
  palette = terminalColors.atuin;
in {
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = false;
    enableNushellIntegration = false;

    # Atuin owns persistent history but not native
    # Up-arrow navigation or automatic keybindings.
    flags = [
      "--disable-ai"
      "--disable-ctrl-r"
      "--disable-up-arrow"
    ];

    # Atuin can create its own config on first run.
    forceOverwriteSettings = true;

    settings = {
      enter_accept = true;
      exit_mode = "return-original";
      filter_mode = "session";
      inline_height = 16;
      invert = true;
      keymap_mode = "emacs";
      prefers_reduced_motion = true;
      show_help = false;
      show_numeric_shortcuts = false;
      show_preview = false;
      show_tabs = false;
      style = "compact";
      workspaces = true;

      keys = {
        accept_past_line_end = false;
        exit_past_line_start = false;
        scroll_exits = false;
      };

      search = {
        filters = [
          "session"
          "workspace"
          "global"
        ];
        shells = "auto";
      };

      theme.name = "rose-pine";

      ui = {
        columns = [
          "duration"
          "time"
          "command"
        ];
        syntax_highlight = false;
      };
    };
  };

  xdg.configFile."atuin/themes/rose-pine.toml".text = ''
    [theme]
    name = "rose-pine"

    [colors]
    Base = "${palette.text}"
    Title = "${palette.iris}"
    Important = "${palette.rose}"
    Annotation = "${palette.subtle}"
    Guidance = "${palette.muted}"
    Muted = "${palette.muted}"
    AlertInfo = "${palette.foam}"
    AlertWarn = "${palette.gold}"
    AlertError = "${palette.love}"
    SyntaxCommand = "${palette.foam}"
    SyntaxFlag = "${palette.iris}"
    SyntaxString = "${palette.pine}"
    SyntaxVariable = "${palette.rose}"
    SyntaxOperator = "${palette.gold}"
    SyntaxComment = "${palette.muted}"
  '';

  # Install Ctrl+R after Atuin initializes its ZLE widgets.
  programs.zsh.initContent = lib.mkOrder 1150 ''
    if (( $+widgets[atuin-search] )); then
      bindkey -M emacs '^R' atuin-search
      bindkey -M viins '^R' atuin-search-viins
      bindkey -M vicmd '^R' atuin-search-vicmd
    fi
  '';
}
