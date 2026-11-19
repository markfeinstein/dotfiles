{ lib, pkgs, ... }: {
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
      solidcraft.enable = pkgs.stdenv.hostPlatform.isDarwin;

      skills = lib.mkAfter [
        "agent-memory"
        "obsidian"
      ];
      mcpPermissions.trustedServers = {
        solidcraft_app = {
          exactCommand = "/Applications/SolidCraft.app/Contents/MacOS/solidcraft-cli";
          exactArgs = [
            "mcp"
            "--connect"
            { loopbackPort = true; }
          ];
          allowAll = true;
        };
      };
    };
  };
}
