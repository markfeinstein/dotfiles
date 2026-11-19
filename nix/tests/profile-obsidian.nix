{
  darwinConfigurations,
  homeConfigurations,
  lib,
  pkgs,
  system,
}:
let
  workVaults = [
    {
      name = "work";
      path = "~/vaults/work";
    }
  ];
  personalVaults = [
    {
      name = "personal";
      path = "~/vaults/personal";
    }
  ];
  customVaults = [
    {
      name = "primary";
      path = "/tmp/obsidian-primary";
    }
  ];
  multiVaults = [
    {
      name = "alpha";
      path = "/tmp/obsidian-alpha";
    }
    {
      name = "beta";
      path = "~/vaults/beta";
    }
  ];
  forcedVaults = [
    {
      name = "forced";
      path = "/tmp/obsidian-forced";
    }
  ];
  homeManagerVaults = [
    {
      name = "home-manager";
      path = "/tmp/obsidian-home-manager";
    }
  ];

  mkDarwinWork = modules: darwinConfigurations.work.extendModules { inherit modules; };
  darwinHome =
    configuration:
    configuration.config.home-manager.users.${configuration.config.profile.user.username};

  topLevelCustom = mkDarwinWork [
    {
      profile = {
        user = {
          username = "downstream";
          email = "downstream@example.com";
        };
        obsidian.vaults = customVaults;
      };
    }
  ];
  topLevelMulti = mkDarwinWork [
    {
      profile.obsidian.vaults = multiVaults;
    }
  ];
  topLevelEmpty = mkDarwinWork [
    {
      profile.obsidian.vaults = [ ];
    }
  ];
  topLevelForced = mkDarwinWork [
    {
      profile.obsidian.vaults = lib.mkForce forcedVaults;
    }
  ];
  homeManagerOverride = mkDarwinWork [
    ({ config, ... }: {
      profile.obsidian.vaults = customVaults;
      home-manager.users.${config.profile.user.username}.profile.obsidian.vaults = homeManagerVaults;
    })
  ];
  invalidDarwinPath = mkDarwinWork [
    {
      profile.obsidian.vaults = [
        {
          name = "invalid";
          path = "relative/path";
        }
      ];
    }
  ];
  invalidDuplicateHome = homeConfigurations."${system}-work".extendModules {
    modules = [
      {
        profile.obsidian.vaults = [
          {
            name = "duplicate";
            path = "/tmp/obsidian-one";
          }
          {
            name = "duplicate";
            path = "/tmp/obsidian-two";
          }
        ];
      }
    ];
  };
  generatedStandalone = homeConfigurations."${system}-work".extendModules {
    modules = [
      {
        profile.obsidian.vaults = multiVaults;
      }
    ];
  };

  invalidDarwinPathResult = builtins.tryEval (
    builtins.deepSeq invalidDarwinPath.config.system.build.toplevel true
  );
  invalidDuplicateHomeResult = builtins.tryEval (
    builtins.deepSeq invalidDuplicateHome.activationPackage true
  );

  actual = {
    darwinWork = (darwinHome darwinConfigurations.work).profile.obsidian.vaults;
    darwinPersonal = (darwinHome darwinConfigurations.personal).profile.obsidian.vaults;
    homeWork = homeConfigurations."${system}-work".config.profile.obsidian.vaults;
    homePersonal = homeConfigurations."${system}-personal".config.profile.obsidian.vaults;
    topLevelCustom = (darwinHome topLevelCustom).profile.obsidian.vaults;
    topLevelMulti = (darwinHome topLevelMulti).profile.obsidian.vaults;
    topLevelEmpty = (darwinHome topLevelEmpty).profile.obsidian.vaults;
    topLevelForced = (darwinHome topLevelForced).profile.obsidian.vaults;
    homeManagerOverride = (darwinHome homeManagerOverride).profile.obsidian.vaults;
  };

  generatedProfile =
    if system == "aarch64-darwin" then
      (darwinHome topLevelMulti).dotfiles.neovim.finalConfigSource
    else
      generatedStandalone.config.dotfiles.neovim.finalConfigSource;
  expectedWorkspaces = pkgs.writeText "expected-obsidian-workspaces.lua" ''
    return ${lib.generators.toLua { } multiVaults}
  '';
in
assert lib.assertMsg (actual.darwinWork == workVaults) "Darwin Work vault fallback changed";
assert lib.assertMsg (
  actual.darwinPersonal == personalVaults
) "Darwin Personal vault fallback changed";
assert lib.assertMsg (
  actual.homeWork == workVaults
) "standalone Home Manager Work vault fallback changed";
assert lib.assertMsg (
  actual.homePersonal == personalVaults
) "standalone Home Manager Personal vault fallback changed";
assert lib.assertMsg (
  actual.topLevelCustom == customVaults
) "ordinary Darwin vaults did not replace the Work fallback";
assert lib.assertMsg (
  actual.topLevelMulti == multiVaults
) "Darwin multi-vault list was not preserved exactly";
assert lib.assertMsg (
  actual.topLevelEmpty == [ ]
) "explicit empty Darwin vault list did not remove all workspaces";
assert lib.assertMsg (
  actual.topLevelForced == forcedVaults
) "forced Darwin vaults did not replace the Work fallback";
assert lib.assertMsg (
  actual.homeManagerOverride == homeManagerVaults
) "ordinary Home Manager override did not take precedence";
assert lib.assertMsg (
  !invalidDarwinPathResult.success
) "invalid Darwin vault path unexpectedly passed validation";
assert lib.assertMsg (
  !invalidDuplicateHomeResult.success
) "duplicate Home Manager vault names unexpectedly passed validation";
pkgs.runCommand "profile-obsidian-inheritance-check" { } ''
  ${pkgs.lua}/bin/lua <<'LUA'
  vim = { g = {} }
  assert(dofile("${generatedProfile}/lua/mark/profile.lua"))

  local actual_workspaces = assert(vim.g.dotfiles_obsidian.workspaces)
  local expected_workspaces = assert(dofile("${expectedWorkspaces}"))
  assert(#actual_workspaces == #expected_workspaces, "generated workspace count differs")
  for index, expected in ipairs(expected_workspaces) do
    local actual_workspace = assert(actual_workspaces[index])
    assert(actual_workspace.name == expected.name, "generated workspace name differs")
    assert(actual_workspace.path == expected.path, "generated workspace path differs")
  end
  LUA
  touch "$out"
''
