{lib, ...}: {
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = lib.mkDefault false;

    nix-direnv.enable = true;
  };
}
