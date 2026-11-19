{ home, lib, pkgs }:
let
  settings = config: config.programs.pi-coding-agent.settings;
  extend = modules: (home.extendModules { inherit modules; }).config;
  base = home.config;
  usage = extend [ { dotfiles.pi.usageDashboard.enable = true; } ];
  isUsage = lib.hasInfix "pi-usage-extension";
  usageSpecs = lib.filter isUsage (settings usage).packages;
in
assert !(lib.any isUsage (settings base).packages);
assert builtins.length usageSpecs == 1;
assert lib.hasPrefix builtins.storeDir (builtins.head usageSpecs);
pkgs.runCommand "pi-profile-options-check" { } ''
  test -f ${builtins.head usageSpecs}/package.json
  touch "$out"
''
