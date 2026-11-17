{ lib, ... }: {
  profile = {
    name = "work";
    obsidian.vaults = lib.mkDefault [
      {
        name = "work";
        path = "~/vaults/work";
      }
    ];
  };

  dotfiles = {
    neovim.features.ai = true;

    pi.skills = lib.mkAfter [
      "agent-memory"
      "obsidian"
    ];
  };
}
