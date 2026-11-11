{lib, ...}: {
  profile.name = "work";

  dotfiles = {
    neovim = {
      features.ai = true;
      obsidian.workspaces = [
        {
          name = "work";
          path = "~/vaults/work";
        }
      ];
    };

    pi.skills = lib.mkAfter [
      "agent-memory"
      "obsidian"
    ];
  };
}
