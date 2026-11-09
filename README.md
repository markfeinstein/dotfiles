# dotfiles

My Nix-managed Home Manager configuration for macOS and Linux. The repository
also exports reusable modules for downstream flakes that want to override the
personal defaults.

## Output contract

On macOS, the profile selects policy and the flake source while the host selects
the nix-darwin output. This repository defines public personal hosts:

```text
darwinConfigurations.m5
```

`--host` and `DOTFILES_HOST` override host selection; otherwise the lifecycle
commands use the macOS LocalHostName and then `hostname -s`. The selected host
configuration must declare the selected `personal` or `work` profile.

Generic `darwinConfigurations.personal` and `.work` outputs remain available for
evaluation and composition. Linux continues to use profile outputs:

```text
homeConfigurations.<system>-personal
homeConfigurations.<system>-work
```

Reusable `common`, `personal`, and `work` modules are exported under
`darwinModules` and `homeModules`. Public host modules are exported as
`darwinModules.hosts.m5`; downstream flakes can compose the profile module with
any additional host module.

`nix/modules/profile.nix` is the single shared profile module. It declares the
profile name and user option schema and, when evaluated by Home Manager, maps
those values to its username, home directory, and state version. The files under
`nix/profiles/` contain only actual `personal` and `work` policy choices.

Home Manager's `home.stateVersion` remains an explicit `mkDefault` because it is
a compatibility contract, not a value that should automatically follow the
installed release. Downstream modules may override it deliberately. The numeric
nix-darwin `system.stateVersion` is a separate platform contract.

Set optional default remote sources independently:

```sh
export DOTFILES_PERSONAL_FLAKE='github:markfeinstein/dotfiles/main'
export DOTFILES_WORK_FLAKE='github:markfeinstein/dotfiles/main'
```

`DOTFILES_FLAKE` or `--flake` overrides the selected profile source for one run.
The selected profile is persisted in `~/.config/dotfiles/profile` when chosen
interactively or with `--profile`; `DOTFILES_PROFILE` remains a temporary
override. Host selection is never persisted because it is derived from the
machine unless explicitly overridden.

## Neovim tooling groups

Neovim's wrapped runtime keeps core editor dependencies separate from optional
Go, Rust, web, infrastructure, SQL, and document-rendering tool groups. All
groups remain enabled by default so existing profiles preserve their current
behavior. Profiles and downstream modules can reduce their closure by disabling
groups whose tools come from project development shells instead:

```nix
dotfiles.neovim.tooling = {
  documents.enable = false;
  rust.enable = false;
  sql.enable = false;
};
```

Disabling a group also removes its configured formatters, linters, and language
servers from Neovim's active configuration.

## Personalization

The standalone outputs intentionally use my public name, email address, and
login name from `nix/modules/profile.nix`. Bootstrap verifies that the
selected output matches the current account, so forks should override
`profile.user` before using those outputs on another account.

The `m5` host enables the fixed Space 1-9 Yabai assignments. The native
configuration is intentionally strict, so provision nine ordinary macOS Spaces
before activating a host that enables fixed targets. The locally signed
development app uses a bundle identifier distinct from published Yabai bundles
so macOS privacy identity does not overlap them.

The `m5` host module owns its OpenLogi device identifier. Device identifiers
are stable hardware inventory rather than credentials, so other public or
private host modules can declare their own value without putting it in the
reusable profile. Declaring the value is more reliable than discovering it
during activation, which would require the device to be connected and the
OpenLogi agent to be running.

Personal host policy that is acceptable to publish belongs in this repository's
`nix/hosts/<host>.nix`. A separate downstream repository can add private or
organization-specific hosts by composing the exported profile module with its
own host module:

```nix
# flake.nix in a downstream repository
{
  inputs = {
    dotfiles.url = "github:markfeinstein/dotfiles/main";
    nixpkgs.follows = "dotfiles/nixpkgs";
    nix-darwin.follows = "dotfiles/nix-darwin";
  };

  outputs = {
    dotfiles,
    nix-darwin,
    ...
  }: {
    darwinConfigurations.work-mac = nix-darwin.lib.darwinSystem {
      modules = [
        dotfiles.darwinModules.work
        ./hosts/work-mac.nix
      ];
    };
  };
}
```

```nix
# hosts/work-mac.nix
{config, ...}: {
  networking.hostName = "work-mac";

  home-manager.users.${config.profile.user.username}.imports = [
    ./work-home.nix
  ];
}
```

The downstream host can add packages, services, identity overrides, MCP trust
policy, and Home Manager modules without changing the reusable work profile.
Commit the downstream lock file and select the source and host independently:

```sh
export DOTFILES_WORK_FLAKE='git+ssh://git@github.com/OWNER/work-dotfiles.git'
rebuild doctor --profile work --host work-mac --remote
```

Bootstrap accepts the same profile/source/host split.

Home Assistant MCP metadata is project configuration and is checked into the
Home Automation repository as `.pi/mcp.json`; `.pi` runtime state remains
ignored. Endpoint and OAuth client metadata may be tracked, while Pi keeps OAuth
tokens in its separate credential store.

No separate Home Assistant MCP permission pin is installed by this repository,
so the permission extension prompts before its calls.

## Install

From a reviewed copy of the bootstrap script:

```sh
./bin/bootstrap --profile personal --host m5 --flake github:markfeinstein/dotfiles/main
```

Bootstrap accepts an existing compatible Nix installation, installs Determinate
Nix when Nix is absent, and activates the selected nix-darwin or Home Manager
profile. The macOS package signature is checked against Determinate Systems'
signing team; Linux uses a versioned installer binary with a pinned SHA-256.
Bootstrap does not clone the repository or provision credentials.

## Repository safety

Local build outputs, editor artifacts, environment files, and common credential
files are excluded by `.gitignore`. Gitleaks extends its default rule set through
`.gitleaks.toml`; `rebuild update` and `rebuild switch` scan staged content before
committing it.

Scan the complete reachable history manually with:

```sh
nix shell --inputs-from . nixpkgs#gitleaks \
  -c gitleaks git --config .gitleaks.toml --redact .
```

GitHub Actions repeats that scan and also evaluates every exported Home Manager
and nix-darwin configuration, checks Nix formatting, validates the workflow,
and runs ShellCheck.

## Local workflow

From a checkout:

```sh
./bin/rebuild doctor --profile personal --host m5 --repo "$PWD"
./bin/rebuild update --profile personal --host m5 --repo "$PWD" --no-update
./bin/rebuild switch --profile personal --host m5 --repo "$PWD" --no-update
```

The explicit `--host m5` is optional on that machine because LocalHostName is
`m5`. `update` may stage, format, build, and commit managed changes but does not
activate them. `switch` additionally activates the exact built output and can
change native applications, macOS policy, services, and other runtime state.
