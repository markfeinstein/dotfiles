{
  lib,
  pkgs,
}: let
  powerlinePillColors = {
    token_in = "terminal:bright-blue";
    token_out = "terminal:bright-blue";
    context_pct = "terminal:bright-blue";
    cost = "terminal:bright-yellow";
    model = "terminal:bright-magenta";
    thinking = "terminal:bright-cyan";
    path = "terminal:bright-blue";
    git = "terminal:bright-cyan";
    gitClean = "terminal:bright-green";
    gitDirty = "terminal:bright-red";
    shell_mode = "terminal:bright-green";
    queue = "terminal:bright-yellow";
  };
in {
  defaultProvider = "github-copilot";
  defaultModel = "gpt-5.6-sol";
  defaultThinkingLevel = "high";
  externalEditor = "nvim";
  hideThinkingBlock = true;
  showCacheMissNotices = true;
  quietStartup = true;
  showHardwareCursor = true;
  fullscreenExitOutput = "resume-hint";
  terminal.imageWidthCells = 80;
  enableInstallTelemetry = false;
  enableAnalytics = false;
  defaultProjectTrust = "ask";
  treeFilterMode = "no-tools";
  defaultTools = ["+codemode"];
  npmCommand = ["${pkgs.nodejs}/bin/npm"];

  subagents = {
    defaultModel = "github-copilot/gpt-6.1-terra";
    defaultThinking = "medium";
    projectRootResolution = "git-root";
    agentOverrides = {
      delegate.disabled = true;
      "codex-exec".disabled = true;
      "codex-exec-writer".disabled = true;
      "cursor-agent".disabled = true;
      "cursor-agent-writer".disabled = true;
      scout = {
        model = "openai-codex/gpt-6-luna";
        thinking = "low";
      };
      researcher = {
        model = "openai-codex/gpt-6-luna";
        thinking = "medium";
      };
      "evidence-auditor" = {
        model = "openai-codex/gpt-6.1-sol";
        thinking = "high";
      };
      worker = {
        model = "github-copilot/gpt-6.1-terra";
        thinking = "high";
        inheritGlobalContext = true;
        skills = ["repository-workflow"];
      };
      reviewer = {
        model = "openai-codex/gpt-6.1-sol";
        thinking = "high";
      };
      oracle = {
        model = "github-copilot/gpt-5.6-sol";
        thinking = "xhigh";
      };
    };
  };

  compaction.modelOverrides."github-copilot/gpt-5.6-sol".reserveTokens = 450000;

  branchSummary.skipPrompt = true;

  powerline = {
    preset = "default";
    placement = "below";
    layout = {
      left = [
        "path"
        "git"
        "model"
        "thinking"
        "shell_mode"
      ];
      right = [
        "token_in"
        "token_out"
        "context_pct"
        "cost"
        "queue"
      ];
      secondary = ["extension_statuses"];
    };
    secondaryOverflow = "drop";
    path.mode = "basename";
    git.polling = "full";
    git.statusTtlMs = 15000;
    model.showThinkingLevel = false;
    context.format = "tokens";
    cost.subscriptionDisplay = "reported-cost";
    pills = true;
    nerdFonts = true;
    bold = true;
    alwaysShowTokens = true;
    pillBackground = "terminal:background";
    pillForeground = "terminal:foreground";
    pillGroups = [
      [
        "token_in"
        "token_out"
        "context_pct"
      ]
      [
        "model"
        "thinking"
      ]
      [
        "path"
        "git"
      ]
    ];
    pillColors = powerlinePillColors;
    pillTextColors = lib.mapAttrs (_: _: "terminal:black") powerlinePillColors;
  };

  sessions = {
    index.dir = "~/.pi/agent/pi-sessions";
    messaging.enable = false;
    subagents.enable = false;
    handoff.enable = false;
    autoTitle = {
      model = "github-copilot/gpt-5.6-luna";
      thinkingLevel = "off";
      refreshTurns = 12;
      tokenBudget = 512;
    };
  };

  retry.maxRetries = 2;
}
