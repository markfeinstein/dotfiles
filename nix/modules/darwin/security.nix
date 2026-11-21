{
  config,
  lib,
  pkgs,
  ...
}:
let
  username = config.profile.user.username;
  timeout = config.dotfiles.sudo.biometricTimeoutSeconds;
in
{
  options.dotfiles.sudo.biometricTimeoutSeconds = lib.mkOption {
    type = lib.types.nullOr (lib.types.ints.between 1 3600);
    default = 30;
    description = "Seconds before sudo dismisses an unanswered biometric dialog. Null uses Apple's untimed Touch ID module.";
  };

  config = {
    security.pam.services.sudo_local = {
      # Use one biometric prompt, then fall through to macOS's password stack.
      touchIdAuth = timeout == null;
      text = lib.mkIf (timeout != null) (
        lib.mkAfter ''
          auth       sufficient     ${pkgs.pam-tid-look}/lib/pam/pam_tid_look.so timeout=${toString timeout}
        ''
      );
    };

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
  };
}
