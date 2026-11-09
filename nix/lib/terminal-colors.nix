let
  roles = {
    base = 0;
    love = 1;
    pine = 2;
    gold = 3;
    foam = 4;
    iris = 5;
    rose = 6;
    text = 7;
    muted = 8;
    subtle = 8;
  };
  mapRoles = names: builtins.mapAttrs (_: index: builtins.elemAt names index) roles;
  starshipNames = [
    "black"
    "red"
    "green"
    "yellow"
    "blue"
    "purple"
    "cyan"
    "white"
    "bright-black"
  ];
  nushellNames = [
    "black"
    "red"
    "green"
    "yellow"
    "blue"
    "purple"
    "cyan"
    "white"
    "dark_gray"
  ];
  fzfPalette = mapRoles [
    "black"
    "red"
    "green"
    "yellow"
    "blue"
    "magenta"
    "cyan"
    "white"
    "bright-black"
  ];
  lazygitPalette = mapRoles [
    "black"
    "red"
    "green"
    "yellow"
    "blue"
    "magenta"
    "cyan"
    "white"
    "default"
  ];
  sgr = index:
    if index < 8
    then toString (30 + index)
    else toString (90 + index - 8);
in {
  inherit roles sgr;
  starship = mapRoles starshipNames;
  zsh = builtins.mapAttrs (_: toString) roles;
  nushell = mapRoles nushellNames;
  atuin = builtins.mapAttrs (_: index: "@ansi_(${toString index})") roles;
  fzf = "fg:${fzfPalette.text},fg+:${fzfPalette.base},bg:-1,bg+:${fzfPalette.text},hl:${fzfPalette.rose},hl+:${fzfPalette.base}:bold,info:${fzfPalette.subtle},prompt:${fzfPalette.iris},pointer:${fzfPalette.love}:bold,marker:${fzfPalette.gold}:bold,spinner:${fzfPalette.foam},header:${fzfPalette.pine},border:${fzfPalette.muted}";
  lazygit = lazygitPalette;
}
