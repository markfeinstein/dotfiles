import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);

// pi-subagents opens worker tabs as `subagent-<run>`, and rex-label-window
// renames them `Agent · …`. A manually renamed worker is left alone unless
// pi-subagents marked the process as a child.
const WORKER_LABEL = /^(?:subagent-[0-9a-f]{8}$|Agent · )/u;
const QUESTION_TOOL = /ask_user|question/iu;

export type RexRunner = (args: string[]) => Promise<string>;

export interface WorkerTab {
  windowId: string;
  worker: boolean;
}

interface ClientList {
  clients?: Array<{
    client_id?: string;
    connection_state?: string;
    info?: { kind?: string; platform?: string };
  }>;
}

export async function resolveWorkerTab(
  run: RexRunner,
  session: string,
  block: string,
  isChild: boolean,
): Promise<WorkerTab | undefined> {
  const inspected = JSON.parse(
    await run(["block", "inspect", "-s", session, block, "--json"]),
  ) as { block?: { window_id?: string } };
  const windowId = inspected.block?.window_id;
  if (!windowId) return undefined;
  const view = JSON.parse(
    await run(["session", "inspect", session, "--json"]),
  ) as { windows?: Array<{ window_id?: string; label?: string }> };
  const label =
    view.windows?.find((window) => window.window_id === windowId)?.label ?? "";
  return { windowId, worker: isChild || WORKER_LABEL.test(label) };
}

/** Mute is per app, so ask every connected Mac app. Phones have no tab mute. */
export async function connectedMacApps(run: RexRunner): Promise<string[]> {
  const listed = JSON.parse(await run(["client", "ls", "--json"])) as ClientList;
  return (listed.clients ?? [])
    .filter(
      (client) =>
        client.info?.kind === "app" &&
        client.info?.platform === "macos" &&
        client.connection_state === "connected" &&
        typeof client.client_id === "string",
    )
    .map((client) => client.client_id as string);
}

/** Applies the latest wanted state in order and skips repeats. */
export function createMuteController(run: RexRunner, windowId: string) {
  let applied: boolean | undefined;
  let chain: Promise<void> = Promise.resolve();
  return {
    set(muted: boolean): Promise<void> {
      chain = chain.then(async () => {
        if (applied === muted) return;
        applied = muted;
        const apps = await connectedMacApps(run).catch(() => []);
        await Promise.all(
          apps.map((client) =>
            run([
              "--timeout",
              "5s",
              "-C",
              client,
              "do",
              "client.tab.mute",
              `window_id=${windowId}`,
              `muted=${muted}`,
            ]).catch(() => undefined),
          ),
        );
      });
      return chain;
    },
  };
}

export interface WorkerMuteOptions {
  env?: NodeJS.ProcessEnv;
  run?: RexRunner;
}

export function registerWorkerMute(
  pi: ExtensionAPI,
  options: WorkerMuteOptions = {},
): Promise<void> | undefined {
  const env = options.env ?? process.env;
  const session = env.REX_SESSION;
  const block = env.REX_BLOCK;
  if (!session || !block) return undefined;
  const run: RexRunner =
    options.run ??
    (async (args) =>
      (
        await execFileAsync(env.REX_BIN_PATH || "rex", ["--autostart=false", ...args], {
          env,
          timeout: 10_000,
        })
      ).stdout);

  let controller: ReturnType<typeof createMuteController> | undefined;
  let running = false;
  let questions = 0;
  const ready = resolveWorkerTab(run, session, block, env.PI_SUBAGENT_CHILD === "1")
    .then((tab) => {
      if (tab?.worker) controller = createMuteController(run, tab.windowId);
    })
    .catch(() => {
      // Muting is best-effort and must never disturb the worker.
    });
  const apply = () =>
    ready.then(() => controller?.set(running && questions === 0));

  // Muted while working; audible when it stops or asks a question.
  pi.on("agent_start", () => {
    running = true;
    void apply();
  });
  pi.on("agent_settled", () => {
    running = false;
    questions = 0;
    void apply();
  });
  pi.on("tool_execution_start", (event) => {
    if (!QUESTION_TOOL.test(event.toolName)) return;
    questions += 1;
    void apply();
  });
  pi.on("tool_execution_end", (event) => {
    if (!QUESTION_TOOL.test(event.toolName)) return;
    questions = Math.max(0, questions - 1);
    void apply();
  });
  pi.on("session_shutdown", async () => {
    running = false;
    await apply();
  });
  return ready;
}

export default function rexWorkerMute(pi: ExtensionAPI) {
  registerWorkerMute(pi);
}
