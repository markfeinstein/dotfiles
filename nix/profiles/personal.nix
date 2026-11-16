{ lib, ... }: {
  profile = {
    name = "personal";
    obsidian.vaults = lib.mkDefault [
      {
        name = "personal";
        path = "~/vaults/personal";
      }
    ];
  };

  dotfiles = {
    credentials.enable = true;
    homelab.enable = true;

    rex.passwordPicker.enable = true;

    neovim.features.ai = true;

    pi = {
      skills = lib.mkAfter [
        "agent-memory"
        "obsidian"
      ];
      mcpPermissions.trustedServers.superlogical.exactUrl = "https://www.superlogical.com/rex/community-mcp";
    };
  };
}
