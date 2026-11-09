# Official Obsidian CLI Reference

Use this reference for the first-party desktop CLI. It reflects official documentation checked **2026-07-19**. The CLI is new and version-sensitive, so inspect the installed version's live help before acting.

## Identify the Right Product

| Product | Executable | Purpose | Desktop required |
| --- | --- | --- | --- |
| Official Obsidian CLI | `obsidian` | Controls Obsidian desktop and local vault semantics | Yes; first command can launch it |
| NotesMD CLI (formerly community `obsidian-cli`) | Product-specific | Third-party direct vault tooling | Product-specific |
| `obsidian-export` | Product-specific | Third-party Markdown export/conversion | No |

Do not silently substitute a community package because its name resembles the official CLI. Remote Sync, Publish, and official Headless workflows require a separate explicit request and current first-party documentation.

## Install or Register the Official CLI

Current official help requires an **Obsidian 1.12.7+ installer**, not only an in-app update from an older installer. `obsidian version` reports the running app version; it does not prove which installer registered the CLI.

1. In Obsidian, open **Settings → General**.
2. Enable **Command line interface**.
3. Follow the registration prompt.
4. Restart the terminal so its environment sees the registration.

If registration fails, first update from a current installer, toggle the setting off and on, and repeat the prompt. Do not make privileged or persistent path changes automatically.

Documented platform behavior:

- **Windows:** installer 1.12.7+ includes an `Obsidian.com` terminal redirector beside `Obsidian.exe`; registration adds the install location to the user's `PATH` after terminal restart.
- **macOS:** registration creates `/usr/local/bin/obsidian` pointing to the app-bundled CLI and can prompt for administrator approval.
- **Linux:** registration copies the CLI to `~/.local/bin/obsidian`; that directory must be on `PATH`. Obsidian 1.13 includes a Flatpak CLI fix.

Offer the official manual repair from current Help only after the user asks to fix installation and approves the exact path or privilege change. Never download a replacement binary or install a same-named package by inference.

## Invocation Grammar

One-shot form:

```text
obsidian [vault=<name-or-id>] <command> [parameter=value ...] [flags ...]
```

Bare `obsidian` starts an interactive TUI. Prefer one-shot commands for auditable automation. `vault:open` is TUI-only.

Rules:

- Parameters use `key=value`; boolean flags are bare words such as `open`, `inline`, or `overwrite`.
- Values containing spaces must remain one shell argument.
- `vault=<name-or-id>` must appear **before the command**.
- If no vault is specified, the CLI uses the vault containing the current directory or the active vault. Do not rely on that for automation.
- `file=<name>` uses wikilink-like resolution and can omit path or extension.
- `path=<path>` is the exact path from the vault root. Prefer it for mutations.
- Many commands default to the active file if neither `file` nor `path` is present. Never accept that default for an unattended write.
- `--copy` copies output to the system clipboard. Use only when explicitly requested.
- CLI content supports `\n` and `\t`, but shell quoting still applies.

For this private installation, default to `vault=Home`, whose approved root is `~/Documents/Home`. Do not enumerate vaults first. Verify with `obsidian vault=Home vault info=path` before a write or whenever this mapping appears stale.

Examples use visible placeholders; replace them with reviewed single arguments rather than shell fragments:

```sh
obsidian vault=Home vault info=path
obsidian vault=Home help search
obsidian vault=Home read path="Notes/Projects/Plan.md"
```

Before using an option, run `obsidian help <command>`. Current changelogs note that unknown options beginning with `--` may be ignored, so a typo is not guaranteed to fail.

## Preflight Sequence

```sh
# Lookup only; does not intentionally launch Obsidian.
command -v obsidian

# These connect to, and may launch, the desktop app.
obsidian version
obsidian help "<command>"
obsidian vault="<vault-id>" vault info=path
```

Before the first invocation, inspect the lookup result and compare it with the documented platform registration: the installer-provided redirector on Windows, the app-bundled CLI symlink on macOS, or the registration-copied binary on Linux. Verify platform code signature or package provenance where available. A repository-local, package-manager, unexpected, or unverifiable executable must be shown to the user and confirmed before it receives vault data; its own `version` or `help` output is not independent provenance.

Use `vaults verbose` only when the list of known vault paths is genuinely needed; its output can disclose private filesystem locations. Compare `vault info=path` with the user-approved root before a mutation.

The app, workspace, core plugins, and services may still be loading. Set a
bounded timeout where the host supports it and retry only after inspecting the
failure. Do not run concurrent CLI mutations. In a version-controlled live
vault, the desktop app may rewrite workspace or plugin state during an otherwise
read-only command. Do not launch it solely for content parsing; use an isolated
fixture or file-level validation unless the acceptance criterion requires the
live index or plugin behavior.

## Command Selection

This is an intent map, not a substitute for live help.

| Intent | Read/preview commands | Mutation commands |
| --- | --- | --- |
| Files and folders | `file`, `files`, `folder`, `folders`, `read`, `open` | `create`, `append`, `prepend`, `move`, `rename`, `delete` |
| Search and structure | `search`, `search:context`, `outline`, `backlinks`, `links`, `unresolved`, `orphans`, `deadends` | `search:open` only changes UI state |
| Properties and aliases | `properties`, `property:read`, `aliases` | `property:set`, `property:remove` |
| Tags and tasks | `tags`, `tag`, `tasks`, `task` | `task ... toggle|done|todo|status=...` |
| Daily notes and templates | `daily:path`, `daily:read`, `templates`, `template:read` | `daily`, `daily:append`, `daily:prepend`, `create ... template=...`; `template:insert` only in a verified interactive active-file workflow |
| Bases and bookmarks | `bases`, `base:views`, `base:query`, `bookmarks` | `base:create`, `bookmark` |
| History and recovery | `diff`, `history`, `history:list`, `history:read` | `history:restore` |

Read [Safety and recovery](safety-and-recovery.md) before structural, destructive, bulk, attachment-cleanup, or restore operations.

## Read-Only Patterns

Prefer an explicit format where the command supports it:

```sh
obsidian vault="<vault-id>" search query="meeting notes" path="Projects" format=json limit=50
obsidian vault="<vault-id>" search:context query="TODO" path="Projects" format=json limit=50
obsidian vault="<vault-id>" backlinks path="Projects/Plan.md" counts format=json
obsidian vault="<vault-id>" links path="Projects/Plan.md"
obsidian vault="<vault-id>" unresolved counts verbose format=json
obsidian vault="<vault-id>" properties path="Projects/Plan.md" format=json
obsidian vault="<vault-id>" tasks path="Projects/Plan.md" todo verbose format=json
obsidian vault="<vault-id>" outline path="Projects/Plan.md" format=json
obsidian vault="<vault-id>" diff path="Projects/Plan.md"
```

Check live help for the exact installed option set. Limit large searches and minimize displayed note content.

### Documented machine formats

There is no documented global `--json` switch for `obsidian`.

- `base:query`: `json`, `csv`, `tsv`, `md`, `paths`
- bookmarks, backlinks, unresolved links, and tags: `json`, `tsv`, `csv`
- tasks: `json`, `tsv`, `csv`
- outline: `tree`, `md`, `json`
- properties: `yaml`, `json`, `tsv`
- search and search context: `text`, `json`
- many list commands also support `total`; some support `verbose`

Other commands return command-specific text. Parse only a documented explicit format, and preserve raw output on parse failure rather than guessing.

## Bounded Mutation Patterns

Run these only after the core workflow's target, preview, and approval rules are satisfied.

```sh
# Create without overwrite, then re-read.
obsidian vault="<vault-id>" create path="Projects/New note.md" content="<short-reviewed-content>"
obsidian vault="<vault-id>" read path="Projects/New note.md"

# Use a configured template; inspect the template and destination first.
obsidian vault="<vault-id>" create path="Trips/Paris.md" template="Travel"

# Set one typed property, then verify it.
obsidian vault="<vault-id>" property:set path="Projects/Plan.md" name="status" value="draft" type=text
obsidian vault="<vault-id>" property:read path="Projects/Plan.md" name="status"

# Rename or move through Obsidian, then validate links.
obsidian vault="<vault-id>" move path="Projects/Old.md" to="Archive/New.md"
obsidian vault="<vault-id>" backlinks path="Archive/New.md" counts format=json
obsidian vault="<vault-id>" unresolved counts verbose format=json

# Trash by configured/default behavior; do not add `permanent` casually.
obsidian vault="<vault-id>" delete path="Scratch/Discard.md"
```

`move` and `rename` update internal links only according to the vault's **Automatically update internal links** setting. Inspect that setting and validate afterward. `delete` uses trash by default; actual recovery behavior depends on vault settings.

`template:insert` has no documented `file=` or `path=` target and writes to the active file. Do not use it in unattended automation. Prefer `create path=... template=...` for a new note or a reviewed exact edit for an existing note; allow insertion only when the user is interactively controlling and has just verified the active file.

For long, private, or shell-significant content, use a reviewed direct file edit instead of `content=`. Command-line arguments can appear in shell history, process inspection, tool logs, or transcripts.

## Output and Error Handling

Official documentation does not specify a stable contract for:

- exit codes;
- stdout versus stderr;
- atomicity;
- app/workspace readiness;
- timeouts; or
- machine-schema compatibility across releases.

Therefore:

1. Record the installed version and exact command.
2. Validate command and option names against live help.
3. Capture bounded output and errors separately where the host permits.
4. Treat malformed, empty, timed-out, or surprising output as failure.
5. Re-read or re-query the intended postcondition after every mutation.
6. Stop the sequence at the first mismatch; do not compensate with a broader command.

## Troubleshooting Boundaries

- If only an old in-app build is present, obtain a current official installer rather than installing an unrelated package.
- After registration, restart the terminal and retry lookup.
- On macOS, inspect the registered symlink before proposing a privileged repair.
- On Linux, inspect the copied binary and `PATH`; update Obsidian if Flatpak integration predates the 1.13 fix.
- On Windows, verify the installer-provided redirector and user `PATH` after terminal restart.
- WSL behavior is not clearly specified by current first-party documentation; do not promise automatic launch across the Windows/WSL boundary.

If troubleshooting requires administrator access, package installation, persistent shell configuration, or replacing a binary, show the exact change and obtain approval first.

## Primary Source

Current command names and options: <https://obsidian.md/help/cli>
