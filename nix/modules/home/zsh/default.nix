{
  config,
  lib,
  ...
}: let
  localZsh = "${config.xdg.configHome}/zsh/local.zsh";
  palette = (import ../../../lib/terminal-colors.nix).zsh;
in {
  imports = [
    ./atuin.nix
    ./rex.nix
  ];

  # Dependencies
  programs = {
    bat.enable = true;
    fd.enable = true;
    fzf.enable = true;
    atuin.enable = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    defaultKeymap = "viins";

    # Atuin handles persistent history.
    history = {
      size = 10000;
      save = 0;
      share = false;
    };

    # Use terminal ANSI colors rather than a fixed theme.
    syntaxHighlighting = {
      enable = true;
      highlighters = [
        "brackets"
        "cursor"
      ];
      styles = {
        default = "fg=${palette.text}";
        unknown-token = "fg=${palette.love},bold";
        reserved-word = "fg=${palette.rose}";
        precommand = "fg=${palette.pine}";
        command = "fg=${palette.foam}";
        builtin = "fg=${palette.foam}";
        function = "fg=${palette.foam}";
        commandseparator = "fg=${palette.iris}";
        path = "fg=${palette.gold}";
        path_pathseparator = "fg=${palette.muted}";
        single-hyphen-option = "fg=${palette.iris}";
        double-hyphen-option = "fg=${palette.iris}";
        single-quoted-argument = "fg=${palette.pine}";
        double-quoted-argument = "fg=${palette.pine}";
        dollar-quoted-argument = "fg=${palette.rose}";
        back-quoted-argument = "fg=${palette.rose}";
        assign = "fg=${palette.iris}";
        redirection = "fg=${palette.gold}";
        comment = "fg=${palette.muted}";
        globbing = "fg=${palette.gold}";
        history-expansion = "fg=${palette.rose}";
        bracket-level-1 = "fg=${palette.foam}";
        bracket-level-2 = "fg=${palette.iris}";
        bracket-level-3 = "fg=${palette.gold}";
        cursor-matchingbracket = "standout";
      };
    };

    initContent = lib.mkMerge [
      (lib.mkOrder 1150 ''
        # Keymap switching.
        zsh-vi-mode() {
          bindkey -v
        }

        zsh-emacs-mode() {
          bindkey -e
        }

        # Edit the current command in $EDITOR.
        autoload -Uz edit-command-line
        zle -N edit-command-line

        # Bind consistently across supported keymaps.
        for keymap in emacs viins vicmd; do
          bindkey -M "$keymap" '^A' beginning-of-line
          bindkey -M "$keymap" '^E' end-of-line
          bindkey -M "$keymap" '^X^E' edit-command-line

          # Alt+Left / Alt+Right.
          bindkey -M "$keymap" '^[b' backward-word
          bindkey -M "$keymap" '^[f' forward-word
        done

        unset keymap
      '')

      # Optional machine-local overrides.
      (lib.mkOrder 2000 ''
        if [[ -r ${lib.escapeShellArg localZsh} ]]; then
          source ${lib.escapeShellArg localZsh}
        fi
      '')
    ];
  };
}
