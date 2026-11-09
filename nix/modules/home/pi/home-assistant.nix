{
  cfg,
  lib,
  pkgs,
}: let
  inlineShellLibrary = import ../../../lib/inline-shell-library.nix {inherit lib;};
  hook = pkgs.writeShellApplication {
    name = "home-automation-pi-worktree-hook";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      export HOME_AUTOMATION_REPO_ROOT=${lib.escapeShellArg cfg.repositoryPath}
      ${inlineShellLibrary ../../../../bin/home-automation-pi-worktree-hook ../../../../bin/lib/worktrees.sh}
    '';
  };
  mcpConfig = pkgs.writeText "home-automation-pi-mcp.json" (builtins.toJSON {
    mcpServers.homeassistant = {
      url = cfg.endpointUrl;
      description = "Inspect Home Assistant runtime context through the pinned OAuth endpoint.";
      oauth = cfg.oauth;
      timeout = 30;
      exposure = "codemode";
    };
  });
  ignoreFile =
    pkgs.writeText "home-automation-gitignore-local" ''      .pi
    '';
in {
  trustedServer = {
    exactUrl = cfg.endpointUrl;
    oauth = cfg.oauth;
  };

  activation = lib.hm.dag.entryAfter ["writeBoundary"] ''
    repo=${lib.escapeShellArg cfg.repositoryPath}
    if [ ! -e "$repo/.git" ]; then
      echo "Skipping Home Assistant Pi project setup: missing $repo/.git"
    else
      if [ -L "$repo" ] || [ ! -d "$repo" ]; then
        echo "Refusing unsafe Home Assistant repository path: $repo" >&2
        exit 1
      fi
      $DRY_RUN_CMD install -d -m 0700 "$repo/.pi" "$repo/.githooks"
      $DRY_RUN_CMD install -m 0600 ${mcpConfig} "$repo/.pi/mcp.json"
      $DRY_RUN_CMD install -m 0755 ${lib.getExe hook} "$repo/.githooks/post-checkout"
      $DRY_RUN_CMD install -m 0644 ${ignoreFile} "$repo/.gitignore-local"

      args=(
        --repo "$repo"
        --label "home-automation Pi MCP"
      )
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        args+=(--dry-run)
      fi
      ${lib.getExe pkgs.configure-repository-worktrees} "''${args[@]}"
    fi
  '';
}
