{lib, ...}: {
  profile.name = "personal";

  dotfiles = {
    credentials.enable = true;
    homelab.enable = true;
    keyboardFirmware.enable = true;

    rex.passwordPicker.enable = true;

    neovim = {
      features.ai = true;
      obsidian.workspaces = [
        {
          name = "personal";
          path = "~/vaults/personal";
        }
      ];
    };

    pi = {
      skills = lib.mkAfter [
        "agent-memory"
        "obsidian"
      ];
      mcpPermissions.trustedServers.superlogical.exactUrl = "https://www.superlogical.com/rex/community-mcp";
    };
  };
}
