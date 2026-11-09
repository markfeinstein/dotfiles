{lib, ...}: {
  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 950 ''
      if [[ -o interactive &&
            "''${TERM_PROGRAM:-}" == rex &&
            -n "''${TTY:-}" &&
            -w "$TTY" ]]; then

        typeset -gi _rex_command_running=0

        # Percent-encode paths for OSC 7.
        _rex_url_encode() {
          emulate -L zsh

          local LC_ALL=C input=$1 output= byte hex
          integer i

          for (( i = 1; i <= ''${#input}; i++ )); do
            byte=''${input[i]}

            if [[ $byte == [A-Za-z0-9._~/-] ]]; then
              output+=$byte
            else
              printf -v hex '%02X' "'$byte"
              output+="%$hex"
            fi
          done

          REPLY=$output
        }

        # Command execution begins.
        _rex_preexec() {
          print -rn -- $'\e]133;B\e\\' >"$TTY"
          print -rn -- $'\e]133;C\e\\' >"$TTY"
          _rex_command_running=1
        }

        # Command finishes and a new prompt begins.
        _rex_precmd() {
          local -i status=$?
          emulate -L zsh

          if (( _rex_command_running )); then
            print -rn -- $'\e]133;D;'"$status"$'\e\\' >"$TTY"
            _rex_command_running=0
          fi

          _rex_url_encode "$PWD"

          print -rn -- \
            $'\e]7;file://'"''${HOST:-localhost}$REPLY"$'\e\\' \
            >"$TTY"

          print -rn -- $'\e]133;A\e\\' >"$TTY"
        }

        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _rex_preexec
        add-zsh-hook precmd _rex_precmd
      fi
    '')

    # Rex-specific keyboard behavior.
    # Runs after the fzf file-picker widget is registered.
    (lib.mkOrder 1160 ''
      if [[ "''${TERM_PROGRAM:-}" == rex ]]; then
        for keymap in emacs viins vicmd; do

          # Rex reserves Ctrl+Space as a prefix.
          bindkey -M "$keymap" '^@' undefined-key

          # Cmd+O opens the fzf Neovim file picker.
          if (( $+widgets[dotfiles-file-picker] )); then
            bindkey -M "$keymap" '\e[111;9u' dotfiles-file-picker
          fi
        done

        unset keymap
      fi
    '')
  ];
}
