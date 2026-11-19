{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.pi;
  jsonFormat = pkgs.formats.json { };
  agentsRoot = ../../../agents;
  skillsRoot = agentsRoot + "/skills";
  availableSkills = lib.filterAttrs (
    name: type: type == "directory" && builtins.pathExists (skillsRoot + "/${name}/SKILL.md")
  ) (builtins.readDir skillsRoot);

  listRelativeFiles =
    root: relative:
    let
      directory = if relative == "" then root else root + "/${relative}";
      entries = builtins.readDir directory;
    in
    lib.concatMap (
      name:
      let
        child = if relative == "" then name else "${relative}/${name}";
      in
      if entries.${name} == "directory" then
        listRelativeFiles root child
      else
        lib.optional (entries.${name} == "regular") child
    ) (builtins.attrNames entries);

  isRuntimeSkillFile =
    relative:
    !(lib.any (directory: relative == directory || lib.hasPrefix "${directory}/" relative) [
      "eval-results"
      "evals"
      "tests"
    ]);

  commonSkills = [
    "agent-skill-engineering"
    "repository-workflow"
    "coordinator-workflow"
    "pull-request-workflow"
  ];
  selectedSkills = lib.unique (commonSkills ++ cfg.skills);
  selectedSkillFiles = lib.concatMap (
    name:
    map (relative: {
      inherit name relative;
    }) (lib.filter isRuntimeSkillFile (listRelativeFiles (skillsRoot + "/${name}") ""))
  ) selectedSkills;

  instructionsFile = agentsRoot + "/global-instructions.md";

  powerlinePackageSource = "git:github.com/markfeinstein/pi-powerline-footer@54aed05107c85cf9421628a981da07ac858a0195";
  commonPackageSpecs = [
    powerlinePackageSource
    "npm:@aliou/pi-guardrails"
    (toString (pkgs.callPackage ../../packages/rpiv-ask-user-question.nix { }))
    "npm:@juicesharp/rpiv-todo"
    "git:github.com/earendil-works/pi-claude-code"
    "npm:pi-intercom"
    "npm:pi-sessions"
    cfg.subagentPackageSpec
    "npm:pi-web-access"
  ];
  optionalPackageSpecs = lib.optional cfg.usageDashboard.enable (
    toString (pkgs.callPackage ../../packages/pi-usage-extension.nix { })
  );
  packageSpecs = lib.unique (commonPackageSpecs ++ optionalPackageSpecs ++ cfg.packageSpecs);
  commonExtraPackages = [
    pkgs.claude-code
    pkgs.nodejs
    pkgs.bun
    pkgs.git
    pkgs.ffmpeg
    pkgs.yt-dlp
  ];
  piExtraPackages = commonExtraPackages ++ cfg.extraPackages;
  piAcpPackage = pkgs.callPackage ../../packages/pi-acp.nix { };
  piAcpSolidcraft = pkgs.writeShellApplication {
    name = "pi-acp-solidcraft";
    text = ''
      export PI_ACP_COMMAND=${lib.escapeShellArg "${piAcpPackage}/bin/pi-acp"}
      export PI_ACP_PI_COMMAND=${lib.escapeShellArg "${pkgs.pi-coding-agent}/bin/pi"}
      ${lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ../../../bin/pi-acp-solidcraft)}
    '';
  };
  rosePineVariants = [
    "rose-pine"
    "rose-pine-moon"
    "rose-pine-dawn"
  ];
  roseThemes = lib.genAttrs rosePineVariants (
    variant: import ../../lib/pi-rose-theme.nix { inherit variant; }
  );
  baseSettings = import ./pi/settings.nix { inherit lib pkgs; };

  piSettings = lib.recursiveUpdate (lib.recursiveUpdate baseSettings cfg.settings) {
    packages = packageSpecs;
  };

  offlinePackageUpdates = cfg.packageUpdates == "offline";
  dryRunPackageUpdateMessage =
    if offlinePackageUpdates then
      "Would reconcile cached Pi extension packages offline with a five-minute deadline"
    else
      "Would update managed Pi extension packages with a five-minute deadline";

  mcpPermissionConfig = jsonFormat.generate "mcp-permissions.json" {
    trustedServers = cfg.mcpPermissions.trustedServers;
  };

  guardrailsConfig = pkgs.writeText "guardrails.json" (builtins.toJSON (import ./pi/guardrails.nix));

  skillFiles = builtins.listToAttrs (
    map (
      entry:
      lib.nameValuePair ".agents/skills/${entry.name}/${entry.relative}" {
        source = skillsRoot + "/${entry.name}/${entry.relative}";
      }
    ) selectedSkillFiles
  );
in
{
  options.dotfiles.pi = {
    enable = lib.mkEnableOption "Pi coding-agent workflow" // {
      default = true;
    };

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "Profile-mergeable Pi settings excluding package specs";
    };

    packageSpecs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Profile-specific floating Pi package specs added to the common suite";
    };

    subagentPackageSpec = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "npm:pi-subagents@0.89.0";
      description = "Single pi-subagents package source; override with a patched local package instead of adding another copy";
    };

    subagentConfig = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = "Profile-mergeable overrides for pi-subagents runtime configuration";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Profile-specific packages added to Pi's common wrapped PATH";
    };

    skills = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (builtins.attrNames availableSkills));
      default = [ ];
      description = "Profile-specific skills added to the common store-managed skill set";
    };

    solidcraft.enable = lib.mkEnableOption "the SolidCraft Pi ACP bridge";

    usageDashboard.enable = lib.mkEnableOption "the pinned @mturley/pi-usage-extension provider usage dashboard";

    packageUpdates = lib.mkOption {
      type = lib.types.enum [
        "update"
        "offline"
      ];
      default = "update";
      description = ''
        How activation runs `pi update --extensions`. `update` may fetch newer
        floating package versions; `offline` sets PI_OFFLINE=1 so activation
        only reconciles cached packages, leaving upgrades to an explicit
        `pi update`.
      '';
    };

    mcpPermissions.trustedServers = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = ''
        Exact non-secret MCP server identity policies. Each server pins
        `exactUrl` (HTTPS) or `exactCommand`/`exactArgs` (stdio). Optional
        `readOnlyTools` lists exact tool names to treat as reads when the server
        omits `readOnlyHint`; explicit non-read or destructive hints still prompt.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Every profile installs Rex, so pin its public docs endpoint once. Only
    # non-destructive annotated reads pass; profiles can still override it.
    dotfiles.pi.mcpPermissions.trustedServers.superlogical.exactUrl =
      lib.mkDefault "https://www.superlogical.com/rex/community-mcp";

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
        "app.thinking.cycle" = [ "ctrl+t" ];
        "app.thinking.toggle" = [ "shift+tab" ];
        "tui.editor.historyPrevious" = [ "alt+p" ];
        "tui.editor.historyNext" = [ "alt+n" ];
      };
      context = instructionsFile;
    };

    home = {
      packages = lib.optional cfg.solidcraft.enable piAcpPackage;

      file = {
        ".agents/AGENTS.md".source = instructionsFile;
        ".pi/agent/themes/rose-pine.json".text = builtins.toJSON roseThemes."rose-pine";
        ".pi/agent/themes/rose-pine-moon.json".text = builtins.toJSON roseThemes."rose-pine-moon";
        ".pi/agent/themes/rose-pine-dawn.json".text = builtins.toJSON roseThemes."rose-pine-dawn";
        ".pi/agent/extensions/powerline-footer/theme.json".text = builtins.toJSON {
          icons.branch = "󰘬";
        };
        ".pi/agent/extensions/mcp-permissions.ts".source = agentsRoot + "/extensions/mcp-permissions.ts";
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
        ".pi/agent/prompts/review-only.md".source = agentsRoot + "/prompts/review-only.md";
        ".config/rpiv-todo/config.json".text = builtins.toJSON {
          maxWidgetLines = 8;
          guidance = {
            promptSnippet = "Track milestones and handoffs when a durable checklist helps";
            promptGuidelines = [
              "Use todos for independently verifiable milestones, handoffs, or work likely to be interrupted. Skip them for short inspect-change-verify tasks."
              "Track the outcome, not each tool call. Keep at most one milestone in progress. Mark it complete only after verification; leave incomplete or failing work open."
              "Before unrelated work, start a new session or reconcile the old list; clear it only after earlier tool calls have settled."
            ];
          };
        };
        ".pi/web-search.json".text = builtins.toJSON {
          allowBrowserCookies = false;
        };
        ".pi/agent/intercom/config.json".text = builtins.toJSON {
          brokerCommand = "${pkgs.bun}/bin/bun";
          brokerArgs = [ ];
          confirmSend = false;
          replyHint = true;
        };
        ".pi/agent/extensions/subagent/config.json".text = builtins.toJSON (lib.recursiveUpdate {
          # Per-run concurrency, not a cross-run fleet-wide hard cap.
          globalConcurrencyLimit = 3;
          activeRunsPrompt = true;
          asyncWidget = false;
          checkpointBeforeDeadlineMs = 300000;
          inlineToolDisplay = "summary";
          maxActiveAsyncRunsPerSession = 2;
          maxSubagentDepth = 1;
          maxSubagentSpawnsPerRun = 64;
          maxSubagentSpawnsPerSession = 256;
          timeoutMs = 3600000;
          worktreeProvider = "worktrunk";
        } cfg.subagentConfig);
        ".pi/agent/npm/node_modules/pi-web-access/node_modules/@earendil-works/pi-coding-agent".source =
          "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
      }
      // skillFiles
      // lib.optionalAttrs cfg.solidcraft.enable {
        ".local/bin/pi-acp-solidcraft".source = "${piAcpSolidcraft}/bin/pi-acp-solidcraft";
      };

      activation = {
        writePiGuardrailsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD install -d -m 0700 "$HOME/.pi/agent/extensions"
          $DRY_RUN_CMD rm -f "$HOME/.pi/agent/extensions/guardrails.json"
          $DRY_RUN_CMD install -m 0600 ${guardrailsConfig} "$HOME/.pi/agent/extensions/guardrails.json"
        '';

        updatePiPackages =
          lib.hm.dag.entryAfter
            [
              "linkGeneration"
              "writePiGuardrailsConfig"
            ]
            ''
              if [ -n "''${DRY_RUN_CMD:-}" ]; then
                echo ${lib.escapeShellArg dryRunPackageUpdateMessage}
              else
                # Set inside the hook: Home Manager's sanitized environment
                # drops flags supplied by the caller.
                PATH=${lib.escapeShellArg (lib.makeBinPath piExtraPackages)}:$PATH \
                  ${lib.optionalString offlinePackageUpdates "PI_OFFLINE=1 "}NPM_CONFIG_UPDATE_NOTIFIER=false \
                  ${pkgs.coreutils}/bin/timeout --signal=TERM --kill-after=10s 300s \
                  ${lib.getExe config.programs.pi-coding-agent.package} update --extensions
              fi
            '';
      };
    };
  };
}
