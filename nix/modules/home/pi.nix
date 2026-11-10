{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.pi;
  jsonFormat = pkgs.formats.json {};
  agentsRoot = ../../../agents;
  skillsRoot = agentsRoot + "/skills";
  availableSkills = lib.filterAttrs (
    name: type:
      type == "directory" && builtins.pathExists (skillsRoot + "/${name}/SKILL.md")
  ) (builtins.readDir skillsRoot);

  listRelativeFiles = root: relative: let
    directory =
      if relative == ""
      then root
      else root + "/${relative}";
    entries = builtins.readDir directory;
  in
    lib.concatMap (
      name: let
        child =
          if relative == ""
          then name
          else "${relative}/${name}";
      in
        if entries.${name} == "directory"
        then listRelativeFiles root child
        else lib.optional (entries.${name} == "regular") child
    ) (builtins.attrNames entries);

  isRuntimeSkillFile = relative:
    !(lib.any (
        directory:
          relative == directory || lib.hasPrefix "${directory}/" relative
      ) [
        "eval-results"
        "evals"
        "tests"
      ]);

  commonSkills = [
    "agent-skill-engineering"
    "repository-workflow"
  ];
  selectedSkills = lib.unique (commonSkills ++ cfg.skills);
  selectedSkillFiles =
    lib.concatMap (
      name:
        map (relative: {
          inherit name relative;
        }) (lib.filter isRuntimeSkillFile (listRelativeFiles (skillsRoot + "/${name}") ""))
    )
    selectedSkills;

  instructionsFile = agentsRoot + "/global-instructions.md";

  powerlinePackageSource = "git:github.com/markfeinstein/pi-powerline-footer@54aed05107c85cf9421628a981da07ac858a0195";
  commonPackageSpecs = [
    powerlinePackageSource
    "npm:@aliou/pi-guardrails"
    "npm:@juicesharp/rpiv-ask-user-question"
    "npm:@juicesharp/rpiv-todo"
    "npm:pi-intercom"
    "npm:pi-sessions"
    "npm:pi-subagents"
    "npm:pi-web-access"
  ];
  packageSpecs = commonPackageSpecs ++ cfg.packageSpecs;
  commonExtraPackages = [
    pkgs.nodejs
    pkgs.bun
    pkgs.ffmpeg
    pkgs.yt-dlp
  ];
  piExtraPackages = commonExtraPackages ++ cfg.extraPackages;
  rosePineVariants = [
    "rose-pine"
    "rose-pine-moon"
    "rose-pine-dawn"
  ];
  roseThemes = lib.genAttrs rosePineVariants (
    variant: import ../../lib/pi-rose-theme.nix {inherit variant;}
  );
  baseSettings = import ./pi/settings.nix {inherit lib pkgs;};

  piSettings = lib.recursiveUpdate (lib.recursiveUpdate baseSettings cfg.settings) {
    packages = packageSpecs;
  };

  mcpPermissionConfig = jsonFormat.generate "mcp-permissions.json" {
    trustedServers = cfg.mcpPermissions.trustedServers;
  };

  guardrailsConfig =
    pkgs.writeText "guardrails.json" (builtins.toJSON (import ./pi/guardrails.nix));

  skillFiles = builtins.listToAttrs (map (
      entry:
        lib.nameValuePair ".agents/skills/${entry.name}/${entry.relative}" {
          source = skillsRoot + "/${entry.name}/${entry.relative}";
        }
    )
    selectedSkillFiles);
in {
  options.dotfiles.pi = {
    enable = lib.mkEnableOption "Pi coding-agent workflow" // {default = true;};

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = {};
      description = "Profile-mergeable Pi settings excluding package specs";
    };

    packageSpecs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Profile-specific floating Pi package specs added to the common suite";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Profile-specific packages added to Pi's common wrapped PATH";
    };

    skills = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (builtins.attrNames availableSkills));
      default = [];
      description = "Profile-specific skills added to the common store-managed skill set";
    };

    mcpPermissions.trustedServers = lib.mkOption {
      inherit (jsonFormat) type;
      default = {};
      description = "Exact non-secret MCP server identity policies";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (name: builtins.hasAttr name availableSkills) selectedSkills;
        message = "dotfiles.pi.skills contains an unavailable skill";
      }
    ];

    programs.pi-coding-agent = {
      enable = true;
      package = pkgs.pi-coding-agent;
      extraPackages = piExtraPackages;
      mutableSettings = false;
      settings = piSettings;
      keybindings = {
        "app.thinking.cycle" = ["ctrl+t"];
        "app.thinking.toggle" = ["shift+tab"];
        "tui.editor.historyPrevious" = ["alt+p"];
        "tui.editor.historyNext" = ["alt+n"];
      };
      context = instructionsFile;
    };

    home = {
      file =
        {
          ".agents/AGENTS.md".source = instructionsFile;
          ".pi/agent/themes/rose-pine.json".text = builtins.toJSON roseThemes."rose-pine";
          ".pi/agent/themes/rose-pine-moon.json".text = builtins.toJSON roseThemes."rose-pine-moon";
          ".pi/agent/themes/rose-pine-dawn.json".text = builtins.toJSON roseThemes."rose-pine-dawn";
          ".pi/agent/extensions/powerline-footer/theme.json".text = builtins.toJSON {
            icons.branch = "󰘬";
          };
          ".pi/agent/extensions/mcp-permissions.ts".source =
            agentsRoot + "/extensions/mcp-permissions.ts";
          ".pi/agent/extensions/mcp-permissions.json".source = mcpPermissionConfig;
          ".config/rpiv-ask-user-question/config.json".text = builtins.toJSON {
            guidance = {
              description = "Ask structured questions only when a blocking decision is required.";
              promptSnippet = "Ask structured questions when ambiguity blocks progress";
              promptGuidelines = [
                "Use ask_user_question only when ambiguity blocks progress; batch all questions into one call."
                "Offer 2-4 distinct options, put the recommendation first, and never add Other or Type something."
                "Use multiSelect only when choices can combine; use previews only for concrete artifacts."
              ];
            };
          };
          ".config/rpiv-todo/config.json".text = builtins.toJSON {
            maxWidgetLines = 8;
            guidance = {
              promptSnippet = "Track multi-step work with the todo tool";
              promptGuidelines = [
                "Use todo for 3+ steps. Keep exactly one task in_progress; complete each task immediately after verification, never in a batch."
                "Status changes use update with id and status. Never complete partial or failing work; represent dependencies with blockedBy."
                "Before unrelated work, start a new session or reconcile the old list; clear it only after earlier tool calls have settled."
              ];
            };
          };
          ".pi/web-search.json".text = builtins.toJSON {
            allowBrowserCookies = false;
          };
          ".pi/agent/intercom/config.json".text = builtins.toJSON {
            brokerCommand = "${pkgs.bun}/bin/bun";
            brokerArgs = [];
            confirmSend = false;
            replyHint = true;
          };
          ".pi/agent/extensions/subagent/config.json".text = builtins.toJSON {
            globalConcurrencyLimit = 12;
            activeRunsPrompt = true;
            asyncWidget = false;
            checkpointBeforeDeadlineMs = 300000;
            inlineToolDisplay = "summary";
            maxActiveAsyncRunsPerSession = 4;
            maxSubagentSpawnsPerRun = 64;
            maxSubagentSpawnsPerSession = 256;
            timeoutMs = 3600000;
            worktreeProvider = "worktrunk";
          };
          ".pi/agent/npm/node_modules/pi-web-access/node_modules/@earendil-works/pi-coding-agent".source = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
        }
        // skillFiles;

      activation = {
        writePiGuardrailsConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
          $DRY_RUN_CMD install -d -m 0700 "$HOME/.pi/agent/extensions"
          $DRY_RUN_CMD rm -f "$HOME/.pi/agent/extensions/guardrails.json"
          $DRY_RUN_CMD install -m 0600 ${guardrailsConfig} "$HOME/.pi/agent/extensions/guardrails.json"
        '';

        updatePiPackages =
          lib.hm.dag.entryAfter [
            "linkGeneration"
            "writePiGuardrailsConfig"
          ] ''
            if [ -n "''${DRY_RUN_CMD:-}" ]; then
              echo "Would update managed Pi extension packages with a five-minute deadline"
            else
              PATH=${lib.escapeShellArg (lib.makeBinPath piExtraPackages)}:$PATH \
                NPM_CONFIG_UPDATE_NOTIFIER=false \
                ${pkgs.coreutils}/bin/timeout --signal=TERM --kill-after=10s 300s \
                ${lib.getExe config.programs.pi-coding-agent.package} update --extensions
            fi
          '';
      };
    };
  };
}
