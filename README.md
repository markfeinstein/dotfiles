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

Machine-local Home Assistant and OpenLogi identifiers are not tracked. Both
integrations are disabled in the public profile and can be enabled by layering a
private Home Manager module over `homeModules.personal`, for example:

```nix
{
  dotfiles.openlogi = {
    enable = true;
    deviceId = "unit:DEVICE_ID";
  };

  dotfiles.pi.homeAssistant = {
    enable = true;
    repositoryPath = "/absolute/path/to/home-automation";
    endpointUrl = "https://home-assistant.example/api/mcp";
    oauth = {
      clientId = "http://localhost:12345";
      callbackUrl = "http://localhost:12345/callback";
      clientName = "Pi";
    };
  };
}
```

The OAuth values above are client metadata, not credentials. Runtime credentials
remain outside the Nix store and repository.

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
