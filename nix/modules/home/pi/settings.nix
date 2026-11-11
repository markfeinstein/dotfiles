{pkgs}: {
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
