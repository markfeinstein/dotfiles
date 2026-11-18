import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { registerWorkerMute, type RexRunner } from "./rex-worker-mute.ts";

type Handler = (event: { toolName?: string }) => unknown;

function fakeRex(label: string) {
  const mutes: string[] = [];
  const run: RexRunner = async (args) => {
    if (args[0] === "block") return JSON.stringify({ block: { window_id: "window:w" } });
    if (args[0] === "session")
      return JSON.stringify({ windows: [{ window_id: "window:w", label }] });
    if (args[0] === "client")
      return JSON.stringify({
        clients: [
          { client_id: "client:mac", connection_state: "connected", info: { kind: "app", platform: "macos" } },
          { client_id: "client:old", connection_state: "disconnected", info: { kind: "app", platform: "macos" } },
          { client_id: "client:phone", connection_state: "connected", info: { kind: "app", platform: "ios" } },
          { client_id: "client:cli", connection_state: "connected", info: { kind: "cli", platform: "macos" } },
        ],
      });
    assert.deepEqual(args.slice(0, 6), ["--timeout", "5s", "-C", "client:mac", "do", "client.tab.mute"]);
    assert.equal(args[6], "window_id=window:w");
    mutes.push(args[7]);
    return "null";
  };
  return { run, mutes };
}

function fakePi() {
  const handlers = new Map<string, Handler>();
  const pi = { on: (name: string, handler: Handler) => handlers.set(name, handler) };
  const emit = async (name: string, event: { toolName?: string } = {}) => {
    await handlers.get(name)?.(event);
    await new Promise((resolve) => setTimeout(resolve, 0));
    await new Promise((resolve) => setTimeout(resolve, 0));
  };
  return { pi: pi as unknown as ExtensionAPI, emit, handlers };
}

const env = { REX_SESSION: "session:s", REX_BLOCK: "block:b" };

test("a worker tab is muted while it works and unmuted for questions and when it stops", async () => {
  const { run, mutes } = fakeRex("Agent · dotfiles · main · 1234abcd");
  const { pi, emit } = fakePi();
  await registerWorkerMute(pi, { env, run });
  await emit("agent_start");
  await emit("tool_execution_start", { toolName: "read" });
  await emit("tool_execution_start", { toolName: "ask_user_question" });
  await emit("tool_execution_end", { toolName: "ask_user_question" });
  await emit("agent_settled");
  await emit("agent_start");
  await emit("session_shutdown");
  assert.deepEqual(mutes, [
    "muted=true",
    "muted=false",
    "muted=true",
    "muted=false",
    "muted=true",
    "muted=false",
  ]);
});

test("a freshly placed subagent tab counts as a worker", async () => {
  const { run, mutes } = fakeRex("subagent-1234abcd");
  const { pi, emit } = fakePi();
  await registerWorkerMute(pi, { env, run });
  await emit("agent_start");
  assert.deepEqual(mutes, ["muted=true"]);
});

test("ordinary tabs are never muted", async () => {
  const { run, mutes } = fakeRex("dotfiles · main");
  const { pi, emit } = fakePi();
  await registerWorkerMute(pi, { env, run });
  await emit("agent_start");
  await emit("agent_settled");
  assert.deepEqual(mutes, []);
});

test("a marked child is a worker even after a manual rename", async () => {
  const { run, mutes } = fakeRex("my renamed tab");
  const { pi, emit } = fakePi();
  await registerWorkerMute(pi, { env: { ...env, PI_SUBAGENT_CHILD: "1" }, run });
  await emit("agent_start");
  assert.deepEqual(mutes, ["muted=true"]);
});

test("outside Rex nothing is registered", () => {
  const { pi, handlers } = fakePi();
  assert.equal(registerWorkerMute(pi, { env: {} }), undefined);
  assert.equal(handlers.size, 0);
});
