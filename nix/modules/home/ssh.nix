{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.ssh.onePasswordAgent;
  profileCfg = config.profile.ssh.onePasswordAgent;
  darwinSocket = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
  agentConfig = (pkgs.formats.toml { }).generate "1password-ssh-agent.toml" {
    "ssh-keys" = map (selector: lib.filterAttrs (_: value: value != null) selector) profileCfg.keys;
  };
in
{
  options.dotfiles.ssh.onePasswordAgent.enable = lib.mkOption {
    type = lib.types.bool;
    default = profileCfg.enable;
    description = "Whether to use the 1Password SSH agent socket on Darwin";
  };

  config = {
    assertions = [
      {
        assertion = !cfg.enable || pkgs.stdenv.hostPlatform.isDarwin;
        message = "dotfiles.ssh.onePasswordAgent.enable is only supported on Darwin";
      }
    ];

    xdg.configFile."1Password/ssh/agent.toml" = lib.mkIf (cfg.enable && profileCfg.keys != [ ]) {
      source = agentConfig;
    };

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
