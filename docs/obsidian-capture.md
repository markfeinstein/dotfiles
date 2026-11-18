# Optional Obsidian capture and reference completion

The shared Neovim configuration provides question, answer, and daily-log capture
plus vault-aware reference completion. Its generic defaults enable these features
for every profile with shared vault folder conventions.

The implementation reads the existing `vim.g.dotfiles_obsidian` profile generated
by `nix/modules/home/neovim.nix`. It reuses the configured workspaces, daily-note
folder and date format, templates folder, inbox, Obsidian lazy loader, and autosave
service. It does not introduce another workspace global, plugin loader, or save
timer.

## Commands and mappings

When capture is enabled and at least one workspace is configured:

| Command | Mapping | Behavior |
| --- | --- | --- |
| `:ObsidianQuestion [question]` | `<leader>oq` | Create or link a question note. |
| `:ObsidianQuestion! [question]` | — | Create or link the question, then open it. |
| `:ObsidianAnswer` | `<leader>oa` | Answer the current question or the question linked on the cursor line. |
| `:ObsidianLog [entry]` | `<leader>ol` | Add a timestamped entry to today's daily note. |

Question templates retain the existing schema. Capture fills `date` and
`asked_in`, preserves an existing question note, and inserts a link either under
the configured daily log heading or at the source cursor. Answer capture updates
`answer`, `status`, `resolved`, and `sources`, and links known people mentions.

Daily-note recognition requires an ISO `YYYY-MM-DD` prefix in the filename and a
path below the configured daily-note folder. This supports nested current daily
paths and legacy subfolders such as `1 - Journals/Daily`, without classifying
weekly or monthly journals as daily notes merely because they share the journal
root.

Reference completion is separately configurable:

- `@` completes configured person notes in vault Markdown buffers and capture
  prompts.
- `[[` in capture prompts delegates to obsidian.nvim's `obsidian-ls`, preserving
  note aliases, headings, labels, and insertion text.
- Normal `[[` completion in note buffers remains solely owned by obsidian.nvim;
  the additional Blink source handles only `@`.
- The shared config enables obsidian.nvim's metadata cache, so previously
  referenced unresolved note targets also appear in `[[` completion without
  creating the note when selected.

## Nix options

All options live under `dotfiles.neovim.obsidian`:

```nix
{
  capture = {
    enable = true;
    questionsFolder = "2 - Notes/Knowledge/Questions";
    questionTemplate = "Question.md";
    logHeading = "## Log";
  };

  references = {
    enable = true;
    peopleFolder = "2 - Notes/People";
  };
}
```

`questionsFolder` and `peopleFolder` are vault-relative. `questionTemplate` is
resolved relative to the existing `dotfiles.neovim.obsidian.templates.folder`,
not from the vault root. Absolute paths and `..` path components are rejected.

## Shared defaults

The generic Neovim module supplies these defaults to every profile:

```nix
dotfiles.neovim.obsidian = {
  capture = {
    enable = true;
    questionsFolder = "2 - Notes/Knowledge/Questions";
  };
  references = {
    enable = true;
    peopleFolder = "2 - Notes/People";
  };
};
```

Each value uses `lib.mkDefault`. A downstream profile can replace the folder
conventions with ordinary option definitions or explicitly disable either feature
without `lib.mkForce`:

```nix
dotfiles.neovim.obsidian = {
  capture.enable = false;
  references.enable = false;
};
```

A downstream configuration still owns its workspace name and absolute vault
path, for example:

```nix
profile.obsidian.vaults = [
  {
    name = "work";
    path = "/Users/mfeinstein/Documents/Carbon";
  }
];
```

The generic module continues to supply the existing template, question-template,
log-heading, inbox, and daily-note defaults. Consumers only need to define them
when intentionally overriding those generic values. With the default daily-note
settings, the resulting path is
`1 - Journals/2026/11-November/2026-11-16-Monday.md`.

## Downstream migration

After the work repository updates its upstream dotfiles input to a revision that
contains these features and verifies the generated configuration, it can remove
the downstream Neovim source overlay that:

1. Copies `config.dotfiles.neovim.finalConfigSource` to a new generated source.
2. Installs `nvim/obsidian_question.lua` as `lua/carbon/obsidian_question.lua`.
3. Installs `nvim/obsidian_refs_source.lua` as
   `lua/carbon/obsidian_refs_source.lua`.
4. Installs `nvim/obsidian_refs_blink.lua` under `plugin/`.
5. Appends `require("carbon.obsidian_question").setup_log(ensure_obsidian_loaded)`
   to the shared `plugin/obsidian.lua`.

Once nothing else imports them, those three downstream Lua modules can also be
removed. The equivalent downstream `dotfiles.neovim.obsidian.capture` and
`references` block can be removed after the upstream revision is integrated and
the downstream lock is updated. The work repository should keep:

- workspace name and absolute vault path;
- any intentional overrides of the shared defaults;
- any unrelated packages, credentials, host settings, or vault scripts.

The QuickAdd JavaScript script is independent of this migration. Do not remove,
install, or overwrite the live-vault script as part of adopting the shared
Neovim implementation.

## Verification

The flake exports `checks.<system>.obsidian-capture`. It runs the actual generated
Neovim profiles and packaged plugin entry points in isolated temporary homes and
vaults. Coverage includes:

- disabled and enabled-without-workspace behavior;
- question creation, existing-note preservation, answering, backlinks, and
  source dates;
- nested and legacy daily paths plus non-daily journal insertion;
- multiple workspaces and path-boundary matching;
- timestamp ordering, legacy formats, nested details, fences, placeholders,
  callouts, and subsequent headings;
- daily-note creation through the real obsidian.nvim plugin, unsaved source and
  destination buffers, cancellation, read-only rejection, loader failure, and
  failed-write recovery;
- people lookup, Blink registration idempotence, and real `obsidian-ls` note,
  alias, and heading completion.

Run the focused check without activation:

```sh
nix build --no-link '.#checks.aarch64-darwin.obsidian-capture'
```

These are headless tests. Prompt responses are supplied programmatically, and
Blink/obsidian-ls behavior is exercised without a live UI. They do not verify an
activated profile, a live Obsidian desktop vault, or interactive menu rendering.
