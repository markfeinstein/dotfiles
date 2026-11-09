{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.profile.user.username;
  loginShell = "/run/current-system/sw${pkgs.nushell.shellPath}";
in {
  environment.shells = [pkgs.nushell];
  users.users.${username}.shell = pkgs.nushell;

  # The primary account predates nix-darwin and is intentionally not listed in
  # users.knownUsers. Repair only its login shell without claiming ownership of
  # account creation or deletion.
  system.activationScripts.nushellLoginShell.text = lib.mkAfter ''
    current_login_shell="$(/usr/bin/dscl . -read ${lib.escapeShellArg "/Users/${username}"} UserShell 2>/dev/null | /usr/bin/awk '/^UserShell: / { print $2 }')"
    if [[ "$current_login_shell" != ${lib.escapeShellArg loginShell} ]]; then
      if [[ -n "''${DRY_RUN_CMD:-}" ]]; then
        echo ${lib.escapeShellArg "Would set ${username}'s login shell to ${loginShell}"}
      else
        echo ${lib.escapeShellArg "setting ${username}'s login shell to ${loginShell}..."} >&2
        /usr/bin/dscl . -create ${lib.escapeShellArg "/Users/${username}"} UserShell ${lib.escapeShellArg loginShell}
      fi
    fi
  '';
}
