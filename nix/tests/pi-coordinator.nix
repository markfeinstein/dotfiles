{ home, lib, pkgs }:
let
  runtime = config: builtins.fromJSON config.home.file.".pi/agent/extensions/subagent/config.json".text;
  settings = config: config.programs.pi-coding-agent.settings;
  base = home.config;
  custom = (home.extendModules {
    modules = [ {
      dotfiles.pi = {
        subagentPackageSpec = "/tmp/pi-subagents-patched";
        subagentConfig.globalConcurrencyLimit = 1;
        settings.subagents.agentOverrides.worker.thinking = "medium";
      };
    } ];
  }).config;
  expectedModels = {
    scout = "openai-codex/gpt-6-luna";
    researcher = "openai-codex/gpt-6-luna";
    evidence-auditor = "openai-codex/gpt-6.1-sol";
    worker = "github-copilot/gpt-6.1-terra";
    reviewer = "openai-codex/gpt-6.1-sol";
    oracle = "github-copilot/gpt-5.6-sol";
  };
  roleChecks = lib.all (name:
    (settings base).subagents.agentOverrides.${name}.machine == "local"
    && (settings base).subagents.agentOverrides.${name}.model == expectedModels.${name}
  ) (builtins.attrNames expectedModels);
in
assert lib.assertMsg roleChecks "native role placement or preserved model choices changed";
assert (runtime base).globalConcurrencyLimit == 3;
assert (runtime base).maxActiveAsyncRunsPerSession == 2;
assert (runtime base).maxSubagentDepth == 1;
assert (runtime base).activeRunsPrompt;
assert (runtime base).checkpointBeforeDeadlineMs == 300000;
assert (runtime base).timeoutMs == 3600000;
assert (runtime custom).globalConcurrencyLimit == 1;
assert (runtime custom).maxActiveAsyncRunsPerSession == 2;
assert (settings custom).subagents.agentOverrides.worker.machine == "local";
assert (settings custom).subagents.agentOverrides.worker.thinking == "medium";
assert builtins.elem "npm:pi-subagents@0.89.0" (settings base).packages;
assert builtins.elem "/tmp/pi-subagents-patched" (settings custom).packages;
assert !(lib.any (lib.hasPrefix "npm:pi-subagents") (settings custom).packages);
assert !(settings base).sessions.messaging.enable;
assert !(settings base).sessions.subagents.enable;
assert !(settings base).sessions.handoff.enable;
assert builtins.hasAttr ".agents/skills/coordinator-workflow/SKILL.md" base.home.file;
assert builtins.hasAttr ".agents/skills/pull-request-workflow/SKILL.md" base.home.file;
assert !(lib.any (lib.hasPrefix ".agents/skills/coordinator-workflow/evals/") (builtins.attrNames base.home.file));
pkgs.runCommand "pi-coordinator-check" { } ''
  ${pkgs.python3}/bin/python ${./pi-coordinator-structure.py} ${../..}
  touch "$out"
''
