{ home, lib, pkgs }:
let
  settings = config: config.programs.pi-coding-agent.settings;
  extend = modules: (home.extendModules { inherit modules; }).config;
  base = home.config;

  usage = extend [ { dotfiles.pi.usageDashboard.enable = true; } ];
  isUsage = lib.hasInfix "pi-usage-extension";
  usageSpecs = lib.filter isUsage (settings usage).packages;

  supersededIds = "!(claude-*-4|claude-*-4-*|gpt-4*|o[0-9]*|gpt-5|gpt-5-*|gpt-5.[0-4]*)";
  hiddenProvider = extend [ { dotfiles.pi.hiddenModels.providers = [ "claude-code" ]; } ];
  allModels = extend [
    {
      dotfiles.pi.hiddenModels = {
        providers = [ ];
        ids = [ ];
      };
    }
  ];
  explicitScope = extend [ { dotfiles.pi.settings.enabledModels = [ "github-copilot/*" ]; } ];

  bridge = settings (extend [ { dotfiles.pi.claudeBridge.enable = true; } ]);
  bridgeOverride = settings (extend [
    {
      dotfiles.pi.claudeBridge.enable = true;
      dotfiles.pi.settings = {
        defaultModel = "claude-sonnet-5-5";
        subagents.agentOverrides.oracle.thinking = "xhigh";
      };
    }
  ]);
  bridgeRoles = {
    scout = [ "haiku" "low" ];
    researcher = [ "sonnet" "medium" ];
    worker = [ "sonnet" "high" ];
    reviewer = [ "opus" "high" ];
    evidence-auditor = [ "opus" "high" ];
    oracle = [ "opus" "high" ];
  };
  bridgeRoleChecks = lib.all (
    role:
    let
      agent = bridge.subagents.agentOverrides.${role};
      expected = bridgeRoles.${role};
    in
    agent.model == "claude-bridge/claude-${builtins.elemAt expected 0}-5-5"
    && agent.thinking == builtins.elemAt expected 1
    && agent.machine == "local"
  ) (builtins.attrNames bridgeRoles);
in
assert !(lib.any isUsage (settings base).packages);
assert builtins.length usageSpecs == 1;
assert lib.hasPrefix builtins.storeDir (builtins.head usageSpecs);
assert (settings base).enabledModels == [ "*/${supersededIds}" ];
assert (settings hiddenProvider).enabledModels == [ "@(!(claude-code))/${supersededIds}" ];
assert !((settings allModels) ? enabledModels);
assert (settings explicitScope).enabledModels == [ "github-copilot/*" ];
assert !(builtins.elem "npm:pi-claude-bridge@0.13.0" (settings base).packages);
assert (settings base).defaultProvider == "github-copilot";
assert lib.count (lib.hasPrefix "npm:pi-claude-bridge") bridge.packages == 1;
assert builtins.elem "npm:pi-claude-bridge@0.13.0" bridge.packages;
assert builtins.elem "git:github.com/earendil-works/pi-claude-code" bridge.packages;
assert bridge.enabledModels == [ "@(!(claude-code))/${supersededIds}" ];
assert bridge.defaultProvider == "claude-bridge";
assert bridge.defaultModel == "claude-opus-5-5";
assert bridge.defaultThinkingLevel == "high";
assert bridge.modelThinkingLevels == {
  "claude-bridge/claude-opus-5-5" = "high";
  "claude-bridge/claude-sonnet-5-5" = "medium";
};
assert bridge.subagents.defaultModel == "claude-bridge/claude-sonnet-5-5";
assert bridge.subagents.defaultThinking == "medium";
assert lib.assertMsg bridgeRoleChecks "Bridge role models or inherited role settings changed";
assert bridge.subagents.agentOverrides.worker.inheritGlobalContext;
assert bridge.subagents.agentOverrides.worker.skills == [ "repository-workflow" ];
assert bridge.subagents.agentOverrides.delegate.disabled;
assert bridgeOverride.defaultModel == "claude-sonnet-5-5";
assert bridgeOverride.defaultProvider == "claude-bridge";
assert bridgeOverride.subagents.agentOverrides.oracle.thinking == "xhigh";
assert bridgeOverride.subagents.agentOverrides.oracle.model == "claude-bridge/claude-opus-5-5";
pkgs.runCommand "pi-profile-options-check" { } ''
  test -f ${builtins.head usageSpecs}/package.json
  touch "$out"
''
