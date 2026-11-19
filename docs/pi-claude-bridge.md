# Claude Bridge preset

`dotfiles.pi.claudeBridge.enable` adds the pinned `pi-claude-bridge` package
(`claudeBridge.packageSpec`, default `npm:pi-claude-bridge@0.13.0`) and makes it
the default provider for fresh sessions and native subagent roles. It is off by
default because it needs a signed-in Claude Code account.

```nix
dotfiles.pi.claudeBridge.enable = true;
```

| Setting | Value |
| --- | --- |
| Fresh sessions | `claude-bridge/claude-opus-5-5`, high thinking |
| Scout | `claude-haiku-5-5`, inherited low thinking |
| Researcher | `claude-sonnet-5-5`, inherited medium thinking |
| Worker | `claude-sonnet-5-5`, inherited high thinking |
| Reviewer, evidence auditor | `claude-opus-5-5`, inherited high thinking |
| Oracle | `claude-opus-5-5`, high thinking (not the GPT oracle's xhigh) |
| Roles without their own model | `claude-sonnet-5-5`, inherited medium thinking |

Only models change; inherited role tools, skills, local placement, limits, and
disabled roles stay as they are. Values in `dotfiles.pi.settings` still win, so
a profile can override any single model or thinking level.

The legacy `pi-claude-code` provider stays installed for existing session
histories and rollback, but its duplicate models are hidden from selection
through `dotfiles.pi.hiddenModels.providers`. The preset changes only the
default for new sessions; saved and running sessions keep their recorded
provider and model. Switching a session back to `claude-code` is a deliberate
owner action, not an automatic fallback.

## Adoption notes

- Bridge requires Pi 1.5.1 or later. The package pin does not lock its
  transitive npm dependencies, such as the Claude Agent SDK.
- It reuses the existing Claude Code login. Check its effective configuration
  (API keys, alternative base URLs, Bedrock, Vertex, `apiKeyHelper`) before
  enabling it on another account, and do not add API keys merely to make a
  subscription setup work.
- Behind a TLS-inspecting proxy, use process-scoped
  `CLAUDE_CODE_CERT_STORE=bundled,system` and the existing
  `NODE_EXTRA_CA_CERTS` bundle. Never disable TLS verification.
- Claude Code shortens MCP read results of roughly 50KB into persisted-file
  previews; reads of roughly 20KB per chunk work. Do not bypass path
  permissions to follow persisted-output files.
- Migrate running sessions one at a time and verify history, tools, and
  approvals before moving others. Do not remove the legacy provider while
  resumable sessions still depend on it.

`checks.<system>.pi-profile-options` verifies the rendered package list, model
scope, defaults, role models, inherited role settings, and profile overrides.
It is an evaluation check, not a live Bridge session.
