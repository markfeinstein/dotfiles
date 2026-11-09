_: {
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--smart-case"
      "--glob=!.git"
      "--max-columns=200"
      "--max-columns-preview"
    ];
  };
}
