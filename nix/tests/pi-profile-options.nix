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
in
assert !(lib.any isUsage (settings base).packages);
assert builtins.length usageSpecs == 1;
assert lib.hasPrefix builtins.storeDir (builtins.head usageSpecs);
assert (settings base).enabledModels == [ "*/${supersededIds}" ];
assert (settings hiddenProvider).enabledModels == [ "@(!(claude-code))/${supersededIds}" ];
assert !((settings allModels) ? enabledModels);
assert (settings explicitScope).enabledModels == [ "github-copilot/*" ];
pkgs.runCommand "pi-profile-options-check" { } ''
  test -f ${builtins.head usageSpecs}/package.json
  touch "$out"
''
