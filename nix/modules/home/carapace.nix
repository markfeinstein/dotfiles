{lib, ...}: {
  programs.carapace = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = lib.mkDefault false;

    environment.CARAPACE_MATCH = true;
  };
}
