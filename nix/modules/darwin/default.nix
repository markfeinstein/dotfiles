{
  imports = [
    ./homebrew.nix
    ./macos.nix
    ./nix-maintenance.nix
    ./nushell.nix
    ./rex.nix
    ./security.nix
    ./yabai.nix
  ];

  # Ensures nix-darwin doesn't try to manage the Nix installation already
  # managed by Determinate.
  nix.enable = false;
}
