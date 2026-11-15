{
  config,
  lib,
  pkgs,
  ...
}:
let
  palette = (import ../../lib/terminal-colors.nix).starship;
  legacyNushellAutoload = "${config.home.homeDirectory}/Library/Application Support/nushell/vendor/autoload/starship.nu";
in
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = false;
      format = "$username$hostname$directory$git_branch$git_status$nix_shell$direnv$line_break$character";
      right_format = "$cmd_duration$status";

      palette = "terminal";
      palettes.terminal = palette;

      character = {
        success_symbol = "[❯](bold pine)";
        error_symbol = "[❯](bold love)";
        vimcmd_symbol = "[❮](bold foam)";
        vimcmd_replace_one_symbol = "[❮](bold love)";
        vimcmd_replace_symbol = "[❮](bold love)";
        vimcmd_visual_symbol = "[❮](bold iris)";
      };

      username = {
        format = "[$user]($style)";
        style_user = "subtle";
        style_root = "bold love";
      };

      hostname = {
        ssh_only = true;
        format = "[@$hostname]($style) ";
        style = "subtle";
      };

      directory = {
        style = "foam";
        repo_root_style = "bold foam";
        before_repo_root_style = "subtle";
        truncation_symbol = "…/";
        read_only_style = "love";
      };

      git_branch = {
        format = "[$symbol$branch(:$remote_branch)]($style) ";
        style = "bold iris";
      };

      git_status = {
        format = "([$all_status$ahead_behind]($style) )";
        style = "rose";
        ahead = "⇡$count";
        behind = "⇣$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
        conflicted = "=$count";
        deleted = "✘$count";
        renamed = "»$count";
        modified = "!$count";
        staged = "+$count";
        untracked = "?$count";
      };

      nix_shell = {
        format = "[$symbol$state]($style) ";
        symbol = "nix ";
        style = "pine";
        heuristic = true;
      };

      direnv = {
        disabled = false;
        format = "[$symbol$loaded/$allowed]($style) ";
        symbol = "env ";
        style = "subtle";
        loaded_msg = "✓";
        unloaded_msg = "!";
        allowed_msg = "✓";
        not_allowed_msg = "?";
        denied_msg = "!";
      };

      cmd_duration = {
        format = "[$duration]($style) ";
        min_time = 2000;
        style = "gold";
      };

      status = {
        disabled = false;
        format = "[$status]($style)";
        style = "bold love";
        recognize_signal_code = true;
      };
    };
  };

  home.activation.removeLegacyNushellStarship = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    legacy_autoload=${lib.escapeShellArg legacyNushellAutoload}
    if [ -f "$legacy_autoload" ] \
      && [ ! -L "$legacy_autoload" ] \
      && ${pkgs.gnugrep}/bin/grep -Fq '/opt/homebrew/bin/starship' "$legacy_autoload"; then
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would remove the stale Homebrew-generated Nushell Starship autoload"
      else
        ${pkgs.coreutils}/bin/rm -f -- "$legacy_autoload"
      fi
    fi
  '';
}
