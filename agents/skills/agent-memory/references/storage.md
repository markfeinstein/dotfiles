# Agent Memory Storage

Memory notes live in the existing Home vault folder:

```text
~/Documents/Home/Resources/Agent Memory/<project>/<type>/<file>.md
```

This package does not create a vault, configure Obsidian, install links, add hooks, run daemons, use MCP, maintain a vector store, or guarantee that a harness invokes it automatically. Source deliverables and native runtime records keep their required destinations.

## Project identity

Use a stable project identity that survives worktrees, harness working directories, and branch names.

Prefer, in order:

1. a user-declared project key;
2. a repository or product identity already present in trusted task context;
3. a parent-approved short name.

Do not derive identity only from `cwd` basename when worktrees or harness sandboxes are involved. Ask when two names are plausible. Do not fetch remote metadata to decide.

## Path rules

Allowed types are exactly:

- `plan`
- `handoff`
- `decision`
- `research`
- `review`
- `context`

Use relative Markdown paths under the approved memory root. Reject absolute paths, `..`, empty components, hidden components, special names, non-`.md` files, symlink components or symlink targets, special files, and hard-linked notes. Bound filenames and content size before writing.

The folder is part of an existing vault. Normal memory content reads and writes should not launch Obsidian. Use the `obsidian` skill only when the task needs app/index-aware semantics such as backlinks, properties, daily-note behavior, plugins, or templates.

## Helper contract

`scripts/memory.py` is a deterministic helper for scoped memory access. It supports only:

```text
--root ROOT list --project PROJECT [--type TYPE]
--root ROOT read --path PROJECT/TYPE/FILE.md
--root ROOT validate --path PROJECT/TYPE/FILE.md
--root ROOT create --project PROJECT --type TYPE --file FILE.md < note.md
--root ROOT update --path PROJECT/TYPE/FILE.md --expected-digest SHA256 < note.md
```

The helper requires an explicit existing `--root`. It must not infer `$HOME`, create the memory root, use fallback paths, read configuration, call Git, run subprocesses, open apps, use the network, delete, move, restore, bulk edit, or echo note bodies in receipts.

The helper uses the Python standard library only. It treats Markdown and frontmatter as opaque UTF-8 bytes: it does not parse YAML, reject duplicate keys, reject YAML tags, validate `am_*` fields, call Obsidian, run subprocesses, or install dependencies. Malformed YAML, duplicate keys, and Python-like tags are stored unchanged when the bytes pass path, type, size, UTF-8, digest, and filesystem checks. Metadata convention review belongs to the agent and user, not this helper.

`validate`, `ok`, and `saved` receipts do not certify frontmatter, schema, metadata, status, links, or lifecycle correctness. File-level validation covers only the requested path/type, regular-file and hard-link checks, byte-size limit, UTF-8 decoding, and digest reporting.

## Write discipline

Before writing, verify the root, path, file type, symlink state, hard-link state, and containment. Use descriptor-relative no-follow APIs where the host supports them. If no safe no-follow path is available, block rather than falling back to string-prefix checks.

Creation is exclusive. Updating requires an expected SHA-256 digest from a fresh read and a fresh source check immediately before replacement. Stop if the target changed after reading.

The helper uses cooperative serialization only. It can reduce races between cooperating helper processes, but it cannot stop Obsidian, editors, shell writes, backup tools, or another process that ignores the lock. Its digest-guarded replacement is not an atomic compare-and-swap against those uncooperative writers; disclose that limit for live use.

Avoid partial truncation. Prefer write-to-temporary-plus-verified-replace for updates. If a failure occurs before mutation, report `blocked`. If a failure occurs after the outcome becomes uncertain, report `unverified` and account for any temporary leftover path without deleting unrelated files.

Receipts should be bounded JSON with status, path, digest, and reason. Do not include the written note body.
