let
  terminalColors = import ./terminal-colors.nix;
  inherit (terminalColors) roles sgr;
in
  builtins.concatStringsSep ":" [
    # Use semantic ANSI slots so file colors follow the active terminal theme.
    "no=0"
    "rs=0"
    "fi=${sgr roles.text}"
    "di=${sgr roles.foam}"
    "ln=${sgr roles.rose}"
    "or=${sgr roles.love}"
    "mi=${sgr roles.love}"
    "ex=${sgr roles.pine}"
    "*.lock=${sgr roles.muted}"
    "*.md=${sgr roles.gold}"
    "*.nix=${sgr roles.foam}"
    "*.nu=${sgr roles.iris}"
    "*.lua=${sgr roles.iris}"
    "*.json=${sgr roles.rose}"
    "*.toml=${sgr roles.rose}"
    "*.yml=${sgr roles.rose}"
    "*.yaml=${sgr roles.rose}"
  ]
