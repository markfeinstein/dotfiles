# dotfiles

My Nix-managed Home Manager configuration for macOS and Linux. The repository
also exports reusable modules for downstream flakes that want to override the
personal defaults.

## Output contract

Profiles select named outputs rather than hostnames:

```text
darwinConfigurations.personal
darwinConfigurations.work
homeConfigurations.<system>-personal
homeConfigurations.<system>-work
```

Reusable modules are exported as named `common`, `personal`, and `work`
attributes under `darwinModules` and `homeModules`. There is no implicit default
module alias.

Set optional default remote sources independently:

```sh
export DOTFILES_PERSONAL_FLAKE='github:markfeinstein/dotfiles/main'
export DOTFILES_WORK_FLAKE='github:markfeinstein/dotfiles/main'
```

`DOTFILES_FLAKE` or `--flake` overrides the selected profile source for one run.
The selected profile is persisted in `~/.config/dotfiles/profile` when chosen
interactively or with `--profile`; `DOTFILES_PROFILE` remains a temporary
override.

## Personalization

The standalone outputs intentionally use my public name, email address, and
login name from `nix/profiles/user-options.nix`. Bootstrap verifies that the
selected output matches the current account, so forks should override
`profile.user` before using those outputs on another account.

The Darwin personal profile enables the fixed Space 1-9 Yabai assignments. Its
native configuration is intentionally strict, so provision nine ordinary macOS
Spaces before the first activation. The work profile leaves fixed assignments
disabled. The locally signed development app uses a bundle identifier distinct
from published Yabai bundles so macOS privacy identity does not overlap them.

The machine-specific OpenLogi device identifier is not tracked. Keep it in a
per-machine module rather than the reusable base. The module does not inherently
need to be private: the identifier is stable hardware inventory, not a
credential. Use a private repository only if you do not want to publish machine
identifiers, paths, hostnames, or similar personal metadata. Declaring the value
is more reliable than discovering it during activation, which would require the
device to be connected and the OpenLogi agent to be running.

A minimal downstream flake can contain:

```nix
# flake.nix
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
    darwinConfigurations.personal = nix-darwin.lib.darwinSystem {
      modules = [
        dotfiles.darwinModules.personal
        ({config, ...}: {
          home-manager.users.${config.profile.user.username}.imports = [
            ./personal-private.nix
          ];
        })
      ];
    };
  };
}
```

```nix
# personal-private.nix
{
  dotfiles.openlogi = {
    enable = true;
    deviceId = "unit:DEVICE_ID";
  };
}
```

Keep this flake in a separate machine-configuration repository, commit its lock
file, and select it for personal builds:

```sh
export DOTFILES_PERSONAL_FLAKE='git+ssh://git@github.com/OWNER/private-dotfiles.git'
rebuild doctor --profile personal --remote
```

Bootstrap should likewise receive the private flake, not the public base, when a
machine needs the OpenLogi configuration.

Home Assistant MCP metadata is project configuration and is checked into the
Home Automation repository as `.pi/mcp.json`; `.pi` runtime state remains
ignored. Endpoint and OAuth client metadata may be tracked, while Pi keeps OAuth
tokens in its separate credential store.

MCP permission pinning remains user policy rather than project policy. A machine
module may optionally add a matching policy so declared read-only tools do not
prompt on every call:

```nix
{
  dotfiles.pi.mcpPermissions.trustedServers.homeassistant = {
    exactUrl = "https://home-assistant.example/api/mcp";
    oauth = {
      clientId = "http://localhost:12345";
      callbackUrl = "http://localhost:12345/callback";
      clientName = "Pi";
    };
  };
}
```

Without that independent pin, the permission extension prompts before Home
Assistant MCP calls.

## Install

From a reviewed copy of the bootstrap script:

```sh
./bin/bootstrap --profile personal --flake github:markfeinstein/dotfiles/main
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
./bin/rebuild doctor --profile personal --repo "$PWD"
./bin/rebuild update --profile personal --repo "$PWD" --no-update
./bin/rebuild switch --profile personal --repo "$PWD" --no-update
```

`update` may stage, format, build, and commit managed changes but does not
activate them. `switch` additionally activates the exact built output and can
change native applications, macOS policy, services, and other runtime state.
