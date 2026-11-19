---
description: Hand this session's work to a fresh Pi session through a handoff file
argument-hint: "[topic] [focus for the next session]"
---
Hand off this session's work to a fresh Pi session. Arguments: "${@:-}". Invoking this command authorizes writing the handoff directory, removing scratch files this session created, and opening one new Rex window running Pi. It does not authorize remote, Jira, GitHub, cloud or Git changes; if one seems needed first, ask.

1. **Inventory.** List what would be lost if this session closed: uncommitted or unmerged work (worktree, branch, path), drafts not yet posted, approvals asked for but not answered, decisions made in chat but not recorded in a ticket, PR or commit, steps whose result was never confirmed, and scratch or credential files this session created. Show the list. If anything should be saved somewhere durable first (a ticket comment, a commit), say so and ask before continuing.
2. **Write the handoff.** Create `~/.pi/agent/handoffs/<YYYY-MM-DD>-<topic>/HANDOFF.md`, using the topic from the arguments or a short slug for the work. Keep it under about 80 lines, in this order:
   - Title, date, and this session's id (`$PI_SESSION_ID`), noting that `session_recall` on it has the detail.
   - **Rules:** ground rules the user set in this session (approvals, people to defer to, writing style, change windows), quoted or close to it.
   - **State:** where the work stands, naming the source of truth for each thread (ticket, PR, file) rather than copying it.
   - **Next:** the next steps in order, each with what to check first.
   - **Open questions:** who owes what answer.
   - **Gotchas:** quirks found the hard way (auth steps, ids, commands that fail).
   - **Cleanup:** leftover worktrees, branches and scratch paths, and who should remove them.
   Mark anything not confirmed by a tool result as "check". No secrets: name where credentials come from, never their values.
3. **Config.** If the next session needs non-secret config this session built by hand (a kubeconfig context, an AWS profile file), copy it into the handoff directory and point to it. Never copy tokens, keys or session caches.
4. **Clean up.** Remove scratch directories and temporary credentials this session created and the next one will not need, each with its own `rm -r` command. List anything left behind on purpose.
5. **Start the next session.** Load the `rex` skill. Open one new window in this Rex session, named after the topic, in the working directory the work needs, running Pi on this session's provider, model and thinking level:
   `rex window new -s "$REX_SESSION" <topic> -c <dir> --json -- pi --provider "$PI_PROVIDER" --model "$PI_MODEL" --thinking "$PI_REASONING_LEVEL" "<start prompt>"`
   The start prompt says which session it takes over from, tells it to read the handoff in full and follow its Rules, to recheck live state before acting, and to get the user's approval in that session before any remote or state-changing action, then names the first thing to report. Include the focus from the arguments if given. Confirm the window started.
6. **Report.** Give the handoff path, the new window's name, what was cleaned up, and anything still only in this session. Then stop working in this session.
