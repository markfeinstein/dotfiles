{lib, ...}: {
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = lib.mkDefault false;

    options = [
      "--cmd"
      "cd"
    ];
  };
}
