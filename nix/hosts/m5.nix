{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.profile.user.username;
in {
  networking.hostName = "m5";

  dotfiles.yabai.fixedSpaceTargets = true;

  home-manager.users.${username}.dotfiles.openlogi = {
    enable = true;
    deviceId = "unit:435a1a87";
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      AllowUsers ${username}
    '';
  };

  users.users.${username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWtC2r2HOrM8v9FCh2vbzQpc4GzJQDWsmRe4PrG18tn m5-onepassword"
  ];

  environment.systemPackages = [pkgs.mosh];

  system.defaults.CustomUserPreferences."com.apple.dock".tilesize = lib.mkForce 32;
}
