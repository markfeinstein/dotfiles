{
  lib,
  pkgs,
  ...
}: let
  terminalColors = import ../../lib/terminal-colors.nix;
in {
  programs = {
    fzf = {
      enable = true;
      enableZshIntegration = true;

      # Atuin owns Ctrl+R.
      historyWidget.zsh.command = "";

      # Follow the active terminal's ANSI color palette.
      defaultOptions = [
        "--color=${terminalColors.fzf}"
      ];
    };

    # Dependencies
    bat.enable = true;
    fd.enable = true;

    zsh.initContent = lib.mkMerge [
      # fzf-tab must load after completion initialization
      # but before syntax highlighting wraps ZLE widgets.
      (lib.mkOrder 1140 ''
        source "${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh"

        zstyle ':completion:*' menu no
        zstyle ':completion:*:descriptions' format '[%d]'
        zstyle ':completion:*' group-name ""
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

        zstyle ':fzf-tab:*' fzf-flags \
          '--height=50%' \
          '--layout=reverse' \
          '--border=rounded' \
          '--info=inline-right' \
          '--prompt=  complete ❯ ' \
          '--color=${terminalColors.fzf}'

        zstyle ':fzf-tab:*' switch-group '<' '>'
        zstyle ':fzf-tab:*' continuous-trigger '/'
      '')

      # File picker widget. Rex owns the Cmd+O keybinding.
      (lib.mkOrder 1150 ''
        _dotfiles_file_picker() {
          emulate -L zsh
          setopt localoptions pipefail

          local selected file
          local -a files

          selected="$(
            fd --type f --color never \
              --no-ignore --max-results 5000 . |
            fzf \
              --preview 'bat --color=always --style=full -- {}' \
              --preview-window 'right:55%' \
              --layout=reverse \
              --multi \
              --exit-0 \
              --prompt '  files❯ ' \
              --bind 'ctrl-d:half-page-down,ctrl-u:half-page-up,scroll-up:up,scroll-down:down'
          )" || {
            zle redisplay
            return 0
          }

          [[ -n "$selected" ]] || return 0

          files=("''${(@f)selected}")

          if (( ''${#files} == 1 )); then
            BUFFER="''${EDITOR:-vi} --"
          else
            BUFFER="''${EDITOR:-vi} -O2 --"
          fi

          for file in "''${files[@]}"; do
            BUFFER+=" ''${(q)file}"
          done

          CURSOR=''${#BUFFER}
          zle accept-line
        }

        zle -N dotfiles-file-picker _dotfiles_file_picker
      '')
    ];
  };
}
