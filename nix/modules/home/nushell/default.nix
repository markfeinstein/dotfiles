{
  config,
  lib,
  pkgs,
  ...
}: let
  palette = (import ../../../lib/terminal-colors.nix).nushell;
  localNu = "${config.xdg.configHome}/nushell/local.nu";
  colorConfig = {
    separator = palette.muted;
    leading_trailing_space_bg = {attr = "n";};
    header = {
      fg = palette.pine;
      attr = "b";
    };
    empty = palette.muted;
    bool = palette.foam;
    int = palette.iris;
    filesize = palette.foam;
    duration = palette.gold;
    datetime = palette.iris;
    range = palette.gold;
    float = palette.iris;
    string = palette.text;
    nothing = palette.muted;
    binary = palette.rose;
    binary_null_char = palette.muted;
    binary_printable = palette.foam;
    binary_whitespace = palette.pine;
    binary_ascii_other = palette.iris;
    binary_non_ascii = palette.gold;
    row_index = {
      fg = palette.pine;
      attr = "b";
    };
    record = palette.text;
    list = palette.text;
    closure = palette.pine;
    glob = palette.foam;
    block = palette.text;
    hints = palette.muted;
    search_result = {attr = "r";};
    shape_binary = palette.iris;
    shape_block = palette.foam;
    shape_bool = palette.foam;
    shape_closure = palette.pine;
    shape_custom = palette.pine;
    shape_datetime = palette.foam;
    shape_directory = palette.foam;
    shape_external = palette.foam;
    shape_externalarg = palette.pine;
    shape_external_resolved = palette.gold;
    shape_filepath = palette.foam;
    shape_flag = palette.iris;
    shape_float = palette.iris;
    shape_glob_interpolation = palette.foam;
    shape_globpattern = palette.foam;
    shape_int = palette.iris;
    shape_internalcall = palette.foam;
    shape_keyword = palette.rose;
    shape_list = palette.foam;
    shape_literal = palette.text;
    shape_match_pattern = palette.pine;
    shape_matching_brackets = {attr = "u";};
    shape_nothing = palette.muted;
    shape_operator = palette.gold;
    shape_pipe = palette.iris;
    shape_range = palette.gold;
    shape_record = palette.foam;
    shape_redirection = palette.iris;
    shape_signature = palette.pine;
    shape_string = palette.pine;
    shape_string_interpolation = palette.foam;
    shape_table = palette.foam;
    shape_variable = palette.iris;
    shape_vardecl = palette.iris;
    shape_raw_string = palette.rose;
    shape_garbage = {
      fg = palette.love;
      attr = "b";
    };
  };
in {
  home.shell.enableNushellIntegration = true;

  programs = {
    carapace.enableNushellIntegration = true;
    direnv.enableNushellIntegration = true;
    fzf.enableNushellIntegration = false;
    starship.enableNushellIntegration = true;
    zoxide.enableNushellIntegration = true;

    nushell = {
      enable = true;
      loadSessionVariables = true;

      settings = {
        show_banner = false;
        edit_mode = "vi";
        buffer_editor = "vi";
      };

      plugins = [
        pkgs.nushellPlugins.formats
      ];

      extraConfig =
        ''
          $env.config.color_config = ('${builtins.toJSON colorConfig}' | from json)
          $env.config.history = ('${builtins.toJSON {
            file_format = "sqlite";
            max_size = 10000;
            sync_on_enter = true;
            isolation = true;
          }}' | from json)
          $env.config.shell_integration = ('${builtins.toJSON {
            osc2 = true;
            osc7 = true;
            osc133 = false;
          }}' | from json)
        ''
        + builtins.readFile ./keybindings.nu
        + ''

          if (${builtins.toJSON localNu} | path exists) {
            source ${builtins.toJSON localNu}
          }
        '';
    };
  };

  home.activation.ensureNushellLocal = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg (builtins.dirOf localNu)}
    $DRY_RUN_CMD touch ${lib.escapeShellArg localNu}
  '';
}
