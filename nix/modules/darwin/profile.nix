{
  config,
  lib,
  ...
}: let
  inherit (config.profile.user) homeDirectory username;
in {
  imports = [../../profiles/user-options.nix];

  assertions = [
    {
      assertion = config.profile.name != null;
      message = "A Darwin profile must set profile.name";
    }
  ];

  system.primaryUser = username;

  users.users.${username} = {
    name = username;
    home = homeDirectory;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.${username}.profile = {
      inherit (config.profile) name;
      user = lib.mkDefault config.profile.user;
    };
  };

  system.stateVersion = 6;
}
