# Pi interactive workflow notes

On Pi 1.5.2, use **Fork** when opening an ordinary session whose original
working directory has disappeared. Start from the intended replacement
directory. Fork makes a new session ID rooted there and leaves the original
intact. Continue only borrows the current directory for that invocation.
This does **not** apply to managed worker sessions; use the owner-checked
[coordinator recovery procedure](pi-coordinator.md#restoration-scope-and-rollout).

## Isolated trials (November 2026)

- **Rex attention:** run each prompt in a disposable background tab. Inspect
  its terminal with `rex block call -s SESSION -b BLOCK program_status` while
  waiting and after cancellation; check the session's active window does not
  change. Guardrails 0.24.0 and the native selector used by the MCP gate both
  went from blocked to done. The stock rpiv 2.15.0 questionnaire remained
  working; supplying the native `blocked` option to its custom UI fixed it.
  This checks the server-side state, not notification delivery by macOS.
- **Guardrails 0.24.0:** a synthetic harmless shell marker matched the
  permission rule. An early deny was ignored; after one quiet second the same
  key denied the call. No real destructive command or approval was needed.
- **Usage 0.10.4:** the real `/usage` dashboard matched a synthetic history.
  It scans the agent session directory and builds a local cache. Reported
  cost is not a subscription invoice. Trial only, not installed by this config.
- **LSP adapter 0.1.4:** with managed installs off and a Nix TypeScript server,
  the real adapter returned definitions and diagnostics in a test harness,
  but did not confine reads to the workspace in all cases. Do not enable it
  globally on the assumption of a workspace boundary.
- **Pi Durable SDK 1.5.2:** a scripted-model SQLite trial stopped the owning
  process after one nested step completed. Reopening and resubmitting the
  same request ID yielded one submission and one final answer; the completed
  step executed once and the interrupted replay-safe step ran again. This is
  process-crash evidence at one checkpoint, not power-loss recovery or an
  exactly-once guarantee for external actions.
