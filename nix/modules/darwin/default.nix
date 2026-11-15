{lib, ...}: {
  imports = [
    ./homebrew.nix
    ./macos.nix
    ./nix-maintenance.nix
    ./nushell.nix
    ./rex.nix
    ./security.nix
    ./yabai.nix
  ];

  # Ensures nix-darwin doesn't try to manage the existing Nix installation.
  nix.enable = false;

  # nix-darwin's Nix activation still moves an unmanaged nix.custom.conf aside
  # even when Nix management is disabled. The /etc activation may also remove
  # the installer's nix.conf because the current system does not declare one.
  # Restore both files after nix-darwin finishes its own Nix activation step.
  system.activationScripts.nix-daemon.text = lib.mkAfter ''
    restored_nix_config=0
    for name in nix.conf nix.custom.conf; do
      current="/etc/nix/$name"
      backup="$current.before-nix-darwin"
      if [ ! -e "$current" ] && [ -e "$backup" ]; then
        echo "restoring unmanaged Nix configuration: $current" >&2
        /bin/mv "$backup" "$current"
        restored_nix_config=1
      fi
    done

    if [ "$restored_nix_config" -eq 1 ]; then
      /bin/launchctl kill HUP system/org.nixos.nix-daemon >/dev/null 2>&1 || true
    fi
  '';
}
