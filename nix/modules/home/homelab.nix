{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.homelab;
in {
  options.dotfiles.homelab = {
    enable = lib.mkEnableOption "personal homelab and infrastructure tooling";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [
        pkgs.age
        pkgs.fluxcd
        pkgs.git-filter-repo
        pkgs.gitleaks
        pkgs.google-cloud-sdk
        pkgs.k9s
        pkgs.kubeconform
        pkgs.kubectl
        pkgs.kubernetes-helm
        pkgs.kustomize
        pkgs.sops
        pkgs.talhelper
        pkgs.talosctl
        pkgs.tailscale
        pkgs.terraform
        pkgs.tpi
        pkgs.yamllint
        pkgs.yq-go
      ];
      description = "Personal homelab packages; extend with normal Nix module list merging";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = cfg.packages;
    home.shellAliases.k = "kubectl";
  };
}
