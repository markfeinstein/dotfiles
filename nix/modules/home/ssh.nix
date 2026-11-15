{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.ssh.onePasswordAgent;
  darwinSocket = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
in
{
  options.dotfiles.ssh.onePasswordAgent.enable =
    lib.mkEnableOption "the 1Password SSH agent socket on Darwin";

  config = {
    assertions = [
      {
        assertion = !cfg.enable || pkgs.stdenv.hostPlatform.isDarwin;
        message = "dotfiles.ssh.onePasswordAgent.enable is only supported on Darwin";
      }
    ];

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      settings."*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      }
      // lib.optionalAttrs (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
        IdentityAgent = darwinSocket;
      };
    };
  };
}
