{
  config,
  pkgs,
  ...
}:
let
  username = config.profile.user.username;
in
{
  security.pam.services.sudo_local.touchIdAuth = true;

  security.sudo.extraConfig = ''
    Defaults always_set_home
  '';

  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      AllowUsers ${username}
    '';
  };

  environment.systemPackages = [ pkgs.mosh ];
}
