{ config, ... }:
let
  username = config.profile.user.username;
in
{
  networking.hostName = "m5";

  home-manager.users.${username}.dotfiles.openlogi = {
    enable = true;
    deviceId = "unit:435a1a87";
  };

  users.users.${username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWtC2r2HOrM8v9FCh2vbzQpc4GzJQDWsmRe4PrG18tn m5-onepassword"
  ];
}
