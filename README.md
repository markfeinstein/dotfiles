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

`--host` and `DOTFILES_HOST` select an exact nix-darwin output. Without an
explicit override, bootstrap and rebuild use the macOS LocalHostName and then
`hostname -s` when a matching host output exists, falling back to the selected
`personal` or `work` profile output otherwise. The selected configuration must
declare the selected profile.

Generic `darwinConfigurations.personal` and `.work` outputs provide the fallback
and remain available for evaluation and composition. Linux continues to use
profile outputs:

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

On personal and work Macs, `sudo` gives Touch ID or Apple Watch 30 seconds,
including during `rebuild`. The dialog shows only the command above Apple’s
standard message. If it’s unanswered, [pam_tid_look](https://github.com/samuelb/pam_tid_look/tree/v0.1.0)
dismisses it and macOS continues to the usual terminal password prompt. Test in
an interactive terminal with `sudo -k -v`: leave the dialog unanswered and
look for `Password:`. No privileged command runs. Set
`dotfiles.sudo.biometricTimeoutSeconds = null;` on a host to restore Apple’s
untimed prompt there. SSH and lock-screen authentication are unchanged.

On Darwin, the common profile enables the 1Password SSH agent by default. A
profile can restrict and order the keys exposed by the agent with selectors for
an item, vault, account, or any combination of them:

```nix
profile.ssh.onePasswordAgent.keys = [
  {
    item = "GitHub SSH Key";
    vault = "Private";
  }
];
```

An empty selector list leaves `~/.config/1Password/ssh/agent.toml` unmanaged so
1Password uses its default key selection. The agent remains disabled by default
for non-Darwin Home Manager outputs.

Profiles also own their reusable Obsidian vault inventory:

```nix
profile.obsidian.vaults = [
  {
    name = "personal";
    path = "~/vaults/personal";
  }
];
```

Neovim consumes this inventory for `obsidian.nvim`, and other modules can use the
same list without depending on editor-specific options. The Personal and Work
inventories are fallback defaults. On Darwin, an explicit top-level list replaces
the selected fallback, including an empty list for no vaults. An ordinary direct
Home Manager definition has final precedence when a downstream configuration
intentionally needs its Home Manager value to differ from the inherited Darwin
value. The default `obsidian.nvim` template folder is `8 - Resources/Templates`
within each vault. The shared Neovim configuration enables obsidian.nvim's
metadata cache so existing notes and previously referenced unresolved targets
participate in `[[` completion. The shared module also enables capture and
reference completion for all profiles with `lib.mkDefault`, using
`2 - Notes/Knowledge/Questions` and `2 - Notes/People`. Downstream profiles can
override the folders or disable either feature normally. Details are covered in
[Optional Obsidian capture and reference completion](docs/obsidian-capture.md).

Both profiles default to `github:markfeinstein/dotfiles/main`. Override their
default remote sources independently when a profile should use a downstream
flake:

```sh
export DOTFILES_WORK_FLAKE='github:OWNER/work-dotfiles/main'
```

`DOTFILES_FLAKE` remains a temporary source override. After `rebuild --flake`
successfully validates the selected configuration and account identity, rebuild
persists that profile's source under `~/.config/dotfiles/sources/`; later bare
invocations reuse it. A persisted local `path:` source that is a Git repository
is treated as a local checkout, so bare `rebuild` updates and commits its lock
file before activation. Bootstrap's `--flake` remains a one-run override. The
selected profile is persisted in `~/.config/dotfiles/profile` when chosen
interactively or with `--profile`; `DOTFILES_PROFILE` remains temporary. Host
selection is never persisted because it is derived from the machine unless
explicitly overridden.

## Neovim tooling groups

Marksman uses hash-pinned upstream release executables on macOS and Linux,
without compiling Marksman or installing a separate .NET SDK/runtime. Its Nix
package runs a version check after installation. Update the release version and
platform hashes together in `nix/packages/marksman-bin.nix`.

The editor stays on the pinned Neovim nightly. Plugins and Tree-sitter grammars
come from the same pinned nixpkgs **without** the nightly overlay so their
package identities match the upstream binary caches. Most plugins are Lua;
compiled parsers and native plugin components can be downloaded rather than
rebuilt because a check dependency changed. Nix still assembles the selected
plugin/parser links locally, and may build a package if its cache entry is
unavailable from the machine's configured substituters. This does not add or
trust new caches. `checks.<system>.neovim-cached-plugins` exercises the configured
nightly with these packages in an isolated home directory.

Nix gives every store file the same timestamp, so a same-size edit could let
`vim.loader` reuse stale bytecode. The wrapper therefore selects
`stdpath("cache")/luac/<sha256 of the resolved config path>` before `init.lua`
enables the loader. A new config target gets a new cache; restarts and rollbacks
reuse an existing one. Old namespaces are not pruned automatically.
`checks.<system>.neovim-cache-namespace` reproduces the stale-cache bug and
verifies the namespace against real Neovim processes. `vim.loader.path` is an
internal Neovim API, so keep that check passing when updating Neovim.

Obsidian is the intentional exception: `nix/packages/obsidian-nvim.nix` pins
[`markfeinstein/obsidian.nvim`](https://github.com/markfeinstein/obsidian.nvim)
to a specific commit and source hash. Its locked npm dependencies are built by
Nix and linked beside the plugin's local Bases worker; no runtime `npm install`
is needed. Node.js is part of Neovim's core wrapped PATH even when web tooling
is disabled. Update the revision/source hash together, and refresh `npmDepsHash`
when the fork's `package-lock.json` changes. `checks.<system>.obsidian-bases`
exercises the packaged worker through the configured Neovim; the existing
`obsidian-capture` check covers capture/reference integration.

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

All Darwin configurations enable the fixed Space 1-9 Yabai assignments. The
native configuration is intentionally strict, so provision nine ordinary macOS
Spaces before activating any managed Mac.

Yabai uses the signed artifact metadata pinned by its flake input. It follows the
latest verified nightly when one is available and falls back to the latest
signed release before the nightly channel has published its first artifact.
Updating the `yabai` input advances that pin without requiring a local signing
certificate. A profile can remain on signed releases explicitly with:

```nix
dotfiles.yabai.installSource = "release";
```

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

Every profile pins the public Rex docs endpoint as the `superlogical` server.
A trust policy can also name exact tools as reads for servers that omit
`readOnlyHint` metadata:

```nix
dotfiles.pi.mcpPermissions.trustedServers.example = {
  exactUrl = "https://mcp.example.com/v2/mcp";
  readOnlyTools = [ "getPage" "search" ];
};
```

The list applies only while the endpoint matches its pin. It never overrides an
explicit `readOnlyHint: false` or `destructiveHint: true`, and it does not accept
wildcards; list future read tools individually after checking their contract.

Pi hides superseded model families (Claude 4, GPT-4, the `o` series, and GPT-5
through 5.4) from model selection and cycling. The list is rendered as one
blocking `enabledModels` glob, so newly released models appear without an edit.
Profiles can replace the id globs (`hiddenModels.ids`) or hide a whole provider:

```nix
dotfiles.pi.hiddenModels.providers = [ "claude-code" ];
```

Set `hiddenModels.ids` and `hiddenModels.providers` to `[ ]` to show every model;
an explicit `dotfiles.pi.settings.enabledModels` replaces the generated glob.

Optional Pi extensions are off by default. A profile can enable the pinned
provider usage dashboard (`@mturley/pi-usage-extension`, unpacked from its npm
tarball without install scripts):

```nix
dotfiles.pi.usageDashboard.enable = true;
```

Profiles with a Claude Code subscription can make `pi-claude-bridge` the default
provider for fresh sessions and subagent roles with
`dotfiles.pi.claudeBridge.enable = true`. See
[Claude Bridge preset](docs/pi-claude-bridge.md).

## Install

Run the standalone bootstrap directly from a reviewed revision:

```sh
curl -fsSL https://raw.githubusercontent.com/markfeinstein/dotfiles/main/bin/bootstrap \
  | /bin/sh -s -- --profile personal
```

Omit `--profile` to choose interactively. On macOS, bootstrap uses a matching
host output when one exists and otherwise falls back to the selected profile
output. Use `--host NAME` only to require an exact output.

Bootstrap accepts an existing compatible Nix installation, installs Determinate
Nix when Nix is absent, and activates the selected nix-darwin or Home Manager
profile. On macOS it first installs Apple's Command Line Tools through
`softwareupdate` when no usable developer directory and SDK are available. The
macOS Nix package signature is checked against Determinate Systems' signing team;
Linux uses a versioned installer binary with a pinned SHA-256. Both macOS
profiles install a pinned, notarized Rex Beta snapshot in `/Applications` after
verifying its bundle and Developer ID team. An existing officially signed Rex
installation is preserved so its built-in updater can manage newer snapshots;
an unverified application at that path is never replaced. Bootstrap does not
clone the repository or provision credentials. A private downstream flake can
be selected on a fresh machine with `--flake` and accessed with an interactively
supplied token:

```sh
curl -fsSL https://raw.githubusercontent.com/markfeinstein/dotfiles/main/bin/bootstrap \
  | /bin/sh -s -- --profile work \
      --flake github:OWNER/work-dotfiles/main --auth-github
```

## Rex pickers

Press <kbd>Ctrl</kbd>+<kbd>Space</kbd> then <kbd>?</kbd> (or run
`rex do rex_docs_picker`) for a native picker of three public reference pages.
The browser opens on the server Mac. Starting **Open Rex Documentation…** from
the command palette doesn't show the picker, because the closing palette
appears to cancel the prompt.
Native prompts appear on every eligible connected Rex app; keep passwords and
history in their existing terminal pickers.

Agents can ask you a question on every connected Rex app, including your phone,
with `rex do ask_user question="…"`. Add `options='["Yes","No"]'` for a list,
`allow_other=true` to also accept typed text, `multiple=true` for several
choices, and `timeout=` (seconds, 300 by default). The JSON result has
`status` (`answered`, `cancelled`, `timeout`, `no_client`, `busy`,
`unsupported`, or `failed`) and, when answered, `answer`. Never put secrets in
the question.

<kbd>Ctrl</kbd>+<kbd>Space</kbd> then <kbd>W</kbd> lists every worktree that
`git-project` knows under `~/dev`, with the current project first. Choosing one
goes to a tab already in that worktree (plain tabs before agent tabs) or opens a
new tab there. <kbd>Ctrl</kbd>+<kbd>Space</kbd> then <kbd>Shift</kbd>+<kbd>W</kbd>
picks a project, asks for a branch, creates the worktree with `git-project
worktree`, and opens it. Worktree paths and branch names appear on every
connected Rex app.

<kbd>Cmd</kbd>+<kbd>L</kbd> lists the HTTP(S) links in the focused pane's newest
20,000 lines, newest first, including clickable terminal links, and opens the
one you choose; <kbd>Ctrl</kbd>+<kbd>Space</kbd> then <kbd>Y</kbd> copies it instead.
Rex's palette has a fixed width, so rows drop `https://` and `www.` and cut long
links in the middle, keeping the host and the end; opening or copying always uses
the full link, but typing filters only on the text shown. The list appears on
every connected Rex app, so a token in a link reaches those devices too.

<kbd>Cmd</kbd>+<kbd>M</kbd> in a Pi pane opens a native picker of every model
with its provider, context and output sizes, abilities, and input/output
prices. It lists Pi's `enabledModels` when the profile sets them, and every
available model otherwise. It has no scope toggle or catalog refresh.

The managed picker floats use the close watcher, not an exiting terminal
process, to restore the originating pane. When the watcher is disabled or
cannot establish who owned focus, Rex's normal close behavior wins.

## Repository safety

Local build outputs, editor artifacts, environment files, and common credential
files are excluded by `.gitignore`. This repository extends Gitleaks' default
rule set through `.gitleaks.toml`; downstream repositories without that file use
the default Gitleaks policy. `rebuild update` and `rebuild switch` scan staged
content before committing it.

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
activate them. Partially staged managed files, including `flake.lock`, are
promoted to their complete working-tree state before the review prompt.
`switch` additionally activates the exact built output and can change native
applications, macOS policy, services, and other runtime state.
