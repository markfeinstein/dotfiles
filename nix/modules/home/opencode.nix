{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.opencode;

  remoteMutationCommands = [
    "git push *"
    "gh pr merge *"
    "gh release create *"
    "gh release delete *"
    "gh release edit *"
    "gh release upload *"
    "gh repo archive *"
    "gh repo delete *"
    "gh repo rename *"
    "gh api --method *"
    "gh api -X *"
    "npm publish *"
    "cargo publish *"
    "terraform apply *"
    "terraform destroy *"
    "kubectl apply *"
    "kubectl create *"
    "kubectl delete *"
    "kubectl patch *"
    "kubectl replace *"
    "kubectl scale *"
    "helm install *"
    "helm rollback *"
    "helm uninstall *"
    "helm upgrade *"
    "ansible-playbook *"
  ];
  destructiveCommands = [
    "rm *"
    "rmdir *"
    "unlink *"
    "shred *"
    "truncate *"
    "dd *"
    "find * -delete *"
    "git reset *"
    "git clean *"
    "git restore *"
    "git checkout -- *"
    "git checkout -f *"
    "git branch -d *"
    "git branch -D *"
    "git worktree remove *"
    "git worktree prune *"
    "git stash drop *"
    "git stash clear *"
    "git reflog expire *"
    "git gc *"
  ];
  privilegedCommands = [
    "sudo *"
    "doas *"
    "rebuild *"
    "darwin-rebuild *"
    "nixos-rebuild *"
    "home-manager switch *"
    "launchctl *"
    "systemctl *"
    "service *"
    "brew services *"
    "shutdown *"
    "reboot *"
    "halt *"
    "poweroff *"
    "kill *"
    "pkill *"
    "killall *"
    "mount *"
    "umount *"
    "chown *"
    "chmod *"
    "defaults write *"
    "defaults delete *"
    "dscl *"
    "diskutil *"
    "nix-collect-garbage *"
    "nix store delete *"
    "nix-store --delete *"
    "opencode service restart *"
    "opencode service stop *"
    "opencode service set *"
    "opencode service unset *"
  ];
  riskyShellCommands = remoteMutationCommands ++ destructiveCommands ++ privilegedCommands;
  askBeforeShell = map (resource: {
    action = "shell";
    inherit resource;
    effect = "ask";
  }) riskyShellCommands;

  serverConfig = {
    "$schema" = "https://opencode.ai/config.json";
    model = "openai/gpt-6.1-terra";
    default_agent = "plan";
    update = "disable";
    snapshots = true;
    formatter = true;
    permissions = askBeforeShell ++ [
      {
        action = "generate_image";
        resource = "*";
        effect = "ask";
      }
    ];
    agents = {
      build.model = "openai/gpt-6.1-terra#xhigh";
      plan.model = "openai/gpt-6.1-terra#high";
      general.model = "openai/gpt-6.1-terra#high";
      explore.model = "openai/gpt-6.1-terra#low";
      compaction.model = "openai/gpt-6.1-terra#medium";
      summary.model = "openai/gpt-6.1-terra#medium";
      title.model = "openai/gpt-6-luna#low";
    };
    compaction = {
      auto = true;
      keep.tokens = 24000;
      buffer = "20%";
    };
    warming = false;
    websearch.provider = "random";
    mcp = {
      timeout = {
        startup = 30000;
        catalog = 30000;
        execution = 43200000;
      };
      servers = lib.optionalAttrs cfg.solidcraft.enable {
        solidcraft = {
          type = "local";
          command = [
            "/Applications/SolidCraft.app/Contents/MacOS/solidcraft-cli"
            "mcp"
          ];
          disabled = false;
          codemode = true;
          protocol = "legacy";
          pool = false;
        };
      };
    };
    worktree.directory = "..";
    experimental = {
      todo = true;
      # Background compaction is still experimental in packaged V2.3.0.
      background_compaction = true;
      subagent_depth = 1;
      location_idle_timeout = "60 minutes";
    };
  };

  cliConfig = {
    "$schema" = "https://opencode.ai/v2/cli.json";
    theme = {
      name = "system";
      mode = "system";
    };
    animations = true;
    cursor.style = "default";
    mouse = true;
    scroll.acceleration = true;
    prompt = {
      editor = true;
      paste = "compact";
      image_preview = true;
    };
    session = {
      sidebar = "auto";
      scrollbar = false;
      submit_scroll = "bottom";
      thinking = "hide";
      grouping = "auto";
      image_preview = true;
      tps = true;
      markdown = "rendered";
      new_location = "inherit";
      permissions = "prompt";
    };
    tabs = {
      mode = "auto";
      scope = "cwd";
      layout = "horizontal";
      indicators = "status";
    };
    diffs = {
      source = "branch";
      wrap = "word";
      tree = true;
      single = false;
      view = "auto";
    };
    attention = {
      notifications = true;
      sound = true;
      volume = 0.3;
      sound_pack = "opencode.default";
    };
    highlights = true;
    terminal = {
      title = true;
      copy = "select";
    };
    mini = {
      thinking = "hide";
      tools = "show";
      shell_output = "hide";
      turn_summary = "show";
      footer = "show";
      splash = "show";
      work_spinner = "density-wave";
      mono = false;
      replay = true;
      replay_limit = 200;
    };
    keybinds = {
      leader = "ctrl+o";
      "open.menu" = "<leader>o";
      "diff.open" = "<leader>d";
      "session.toggle.thinking" = "<leader>shift+t";
    };
    leader.timeout = 2000;
    debug = {
      devtools = false;
      timing = false;
      turn_tokens = false;
    };
    experimental = {
      "new-designs" = true;
      "client-mcp" = true;
    };
  };
in
{
  options.dotfiles.opencode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to manage the global OpenCode V2 configuration";
    };

    solidcraft.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.profile.name == "personal" && pkgs.stdenv.hostPlatform.isDarwin;
      description = "Whether to configure the local SolidCraft MCP server";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.versions.major pkgs.opencode.version == "2";
        message = "dotfiles.opencode requires OpenCode v2";
      }
    ];

    xdg.configFile = {
      "opencode/opencode.json" = {
        force = true;
        text = builtins.toJSON serverConfig;
      };
      "opencode/cli.json" = {
        force = true;
        text = builtins.toJSON cliConfig;
      };
    };
  };
}
