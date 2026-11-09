_: let
  palette = (import ../../lib/terminal-colors.nix).lazygit;
in {
  programs.lazygit = {
    enable = true;
    enableNushellIntegration = true;
    enableZshIntegration = true;

    settings = {
      gui = {
        colorScheme = "auto";
        expandFocusedSidePanel = true;
        filterMode = "fuzzy";
        nerdFontsVersion = "3";
        showDivergenceFromBaseBranch = "arrowAndNumber";
        skipNoStagedFilesWarning = true;
        skipRewordInEditorWarning = true;
        skipSwitchWorktreeOnCheckoutWarning = true;

        theme = {
          activeBorderColor = [
            palette.foam
            "bold"
          ];
          inactiveBorderColor = [palette.muted];
          searchingActiveBorderColor = [
            palette.gold
            "bold"
          ];
          optionsTextColor = [palette.iris];
          selectedLineFgColor = [
            palette.text
            "bold"
          ];
          selectedLineBgColor = ["reverse"];
          inactiveViewSelectedLineBgColor = ["dim"];
          cherryPickedCommitFgColor = [palette.foam];
          cherryPickedCommitBgColor = [palette.rose];
          unstagedChangesColor = [palette.love];
          defaultFgColor = [palette.text];
        };
      };

      git = {
        autoWrapCommitMessage = true;
        ignoreWhitespaceInDiffView = true;
        parseEmoji = true;
      };
      os.editPreset = "nvim";
      update.method = "never";
    };
  };
}
