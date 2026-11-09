{
  imports = [
    ../profile.nix
    ./bat.nix
    ./carapace.nix
    ./credentials.nix
    ./delta.nix
    ./direnv.nix
    ./fzf.nix
    ./git.nix
    ./github.nix
    ./go.nix
    ./homelab.nix
    ./jq.nix
    ./keyboard-firmware.nix
    ./lazygit.nix
    ./lifecycle.nix
    ./neovim.nix
    ./nushell
    ./openlogi.nix
    ./packages.nix
    ./pi.nix
    ./ripgrep.nix
    ./rex.nix
    ./shell.nix
    ./ssh.nix
    ./starship.nix
    ./theme.nix
    ./worktrunk.nix
    ./yabai.nix
    ./zoxide.nix
    ./zsh
  ];

  programs.home-manager.enable = true;
}
