{
  config,
  lib,
  ...
}: {
  imports = [./user-options.nix];

  home = {
    username = lib.mkDefault config.profile.user.username;
    homeDirectory = lib.mkDefault config.profile.user.homeDirectory;
    stateVersion = lib.mkDefault "26.11";
  };
}
