_: {
  programs.delta = {
    enable = true;
    enableGitIntegration = true;

    options = {
      syntax-theme = "none";
      true-color = "never";
      detect-dark-light = "auto";

      line-numbers = true;
      navigate = true;

      plus-style = "green";
      minus-style = "red";
      plus-emph-style = "bold green";
      minus-emph-style = "bold red";

      file-style = "bold blue";
      hunk-header-style = "cyan";
    };
  };
}
