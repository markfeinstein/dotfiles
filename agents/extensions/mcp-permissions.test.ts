import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type {
  ExtensionAPI,
  RegisteredMcpServer,
} from "@earendil-works/pi-coding-agent";
import {
  evaluateMcpPermission,
  readPermissionConfig,
  registerMcpPermissions,
  resolveTrustedServers,
} from "./mcp-permissions.ts";

const SOLIDCRAFT_COMMAND =
  "/Applications/SolidCraft.app/Contents/MacOS/solidcraft-cli";

function withTemporaryDirectories(
  run: (homeDirectory: string, cwd: string) => void,
): void {
  const root = mkdtempSync(join(tmpdir(), "mcp-permissions-"));
  const homeDirectory = join(root, "home");
  const cwd = join(root, "project");
  try {
    run(homeDirectory, cwd);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function solidcraftServer(args: string[]): RegisteredMcpServer {
  return {
    name: "solidcraft-app",
    config: {
      command: SOLIDCRAFT_COMMAND,
      args,
      env: {},
      exposure: "direct",
    },
    extensionPath: "/tmp/session-mcp-extension.js",
  };
}

test("readPermissionConfig accepts pinned stdio servers with promptless access", () => {
  const root = mkdtempSync(join(tmpdir(), "mcp-permissions-config-"));
  const path = join(root, "mcp-permissions.json");
  try {
    writeFileSync(
      path,
      JSON.stringify({
        trustedServers: {
          superlogical: {
            exactUrl: "https://www.superlogical.com/rex/community-mcp",
          },
          solidcraft_app: {
            exactCommand: SOLIDCRAFT_COMMAND,
            exactArgs: ["mcp", "--connect", { loopbackPort: true }],
            allowAll: true,
          },
        },
      }),
    );

    const trustedServers = readPermissionConfig(path).trustedServers;
    assert.deepEqual(trustedServers.get("superlogical"), {
      exactUrl: "https://www.superlogical.com/rex/community-mcp",
      allowAll: false,
    });
    assert.deepEqual(trustedServers.get("solidcraft_app"), {
      exactCommand: SOLIDCRAFT_COMMAND,
      exactArgs: ["mcp", "--connect", { loopbackPort: true }],
      allowAll: true,
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("resolveTrustedServers keeps exact HTTPS server trust", () => {
  withTemporaryDirectories((homeDirectory, cwd) => {
    const configDirectory = join(homeDirectory, ".pi", "agent");
    mkdirSync(configDirectory, { recursive: true });
    writeFileSync(
      join(configDirectory, "mcp.json"),
      JSON.stringify({
        mcpServers: {
          superlogical: {
            url: "https://www.superlogical.com/rex/community-mcp",
            exposure: "codemode",
          },
        },
      }),
    );
    const policies = new Map([
      [
        "superlogical",
        {
          exactUrl: "https://www.superlogical.com/rex/community-mcp",
          allowAll: false,
        },
      ],
    ]);

    const trusted = resolveTrustedServers(
      homeDirectory,
      cwd,
      false,
      policies,
    );

    assert.deepEqual(trusted.get("superlogical"), { allowAll: false });
  });
});

test("resolveTrustedServers trusts the registered SolidCraft loopback server", () => {
  withTemporaryDirectories((homeDirectory, cwd) => {
    const policies = new Map([
      [
        "solidcraft_app",
        {
          exactCommand: SOLIDCRAFT_COMMAND,
          exactArgs: ["mcp", "--connect", { loopbackPort: true as const }],
          allowAll: true,
        },
      ],
    ]);

    const trusted = resolveTrustedServers(
      homeDirectory,
      cwd,
      false,
      policies,
      [solidcraftServer(["mcp", "--connect", "127.0.0.1:49209"])],
    );

    assert.deepEqual(trusted.get("solidcraft_app"), { allowAll: true });
  });
});

test("resolveTrustedServers rejects altered SolidCraft connection arguments", () => {
  withTemporaryDirectories((homeDirectory, cwd) => {
    const policies = new Map([
      [
        "solidcraft_app",
        {
          exactCommand: SOLIDCRAFT_COMMAND,
          exactArgs: ["mcp", "--connect", { loopbackPort: true as const }],
          allowAll: true,
        },
      ],
    ]);

    for (const args of [
      ["mcp", "--connect", "example.com:49209"],
      ["mcp", "--connect", "127.0.0.1:49209", "--allow-any-path"],
    ]) {
      const trusted = resolveTrustedServers(
        homeDirectory,
        cwd,
        false,
        policies,
        [solidcraftServer(args)],
      );
      assert.equal(trusted.has("solidcraft_app"), false);
    }
  });
});

test("allowAll bypasses destructive and missing MCP annotations", () => {
  assert.deepEqual(
    evaluateMcpPermission(
      "mcp__solidcraft_app__execute",
      { destructiveHint: true },
      true,
      true,
    ),
    { kind: "allow" },
  );
  assert.equal(
    evaluateMcpPermission(
      "mcp__solidcraft_app__execute",
      undefined,
      true,
    ).kind,
    "prompt",
  );
});

test("registered SolidCraft calls pass the permission gate without UI", async () => {
  const root = mkdtempSync(join(tmpdir(), "mcp-permissions-gate-"));
  const configPath = join(root, "mcp-permissions.json");
  const handlers = new Map<string, (event: unknown, context: any) => unknown>();
  let prompted = false;
  try {
    writeFileSync(
      configPath,
      JSON.stringify({
        trustedServers: {
          solidcraft_app: {
            exactCommand: SOLIDCRAFT_COMMAND,
            exactArgs: ["mcp", "--connect", { loopbackPort: true }],
            allowAll: true,
          },
        },
      }),
    );
    const pi = {
      on(event: string, handler: (event: unknown, context: any) => unknown) {
        handlers.set(event, handler);
      },
      getMcpServers() {
        return [solidcraftServer(["mcp", "--connect", "127.0.0.1:49209"])];
      },
      getAllTools() {
        return [
          {
            name: "mcp__solidcraft_app__execute",
            annotations: { destructiveHint: true },
          },
        ];
      },
    } as unknown as ExtensionAPI;

    registerMcpPermissions(pi, { configPath, homeDirectory: root });
    await handlers.get("session_start")?.(
      {},
      {
        cwd: join(root, "project"),
        isProjectTrusted: () => false,
      },
    );
    const result = await handlers.get("tool_call")?.(
      {
        toolName: "mcp__solidcraft_app__execute",
        input: {},
      },
      {
        hasUI: true,
        ui: {
          select() {
            prompted = true;
            return "Deny";
          },
        },
      },
    );

    assert.equal(result, undefined);
    assert.equal(prompted, false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

const DOCS_URL = "https://mcp.example.com/v2/mcp";

test("readPermissionConfig keeps exact read-only tool lists and rejects unsafe ones", () => {
  const root = mkdtempSync(join(tmpdir(), "mcp-permissions-readonly-"));
  const path = join(root, "mcp-permissions.json");
  try {
    writeFileSync(
      path,
      JSON.stringify({
        trustedServers: {
          docs: { exactUrl: DOCS_URL, readOnlyTools: ["getPage", "search", "getPage"] },
          local: {
            exactCommand: "/usr/local/bin/local-mcp",
            exactArgs: [],
            readOnlyTools: ["list"],
          },
          wildcard: { exactUrl: DOCS_URL, readOnlyTools: ["get*"] },
          mixed: { exactUrl: DOCS_URL, readOnlyTools: ["getPage", 1] },
          scalar: { exactUrl: DOCS_URL, readOnlyTools: "getPage" },
          empty: { exactUrl: DOCS_URL, readOnlyTools: [] },
        },
      }),
    );

    const trustedServers = readPermissionConfig(path).trustedServers;
    assert.deepEqual(trustedServers.get("docs"), {
      exactUrl: DOCS_URL,
      allowAll: false,
      readOnlyTools: ["getPage", "search"],
    });
    assert.deepEqual(trustedServers.get("local"), {
      exactCommand: "/usr/local/bin/local-mcp",
      exactArgs: [],
      allowAll: false,
      readOnlyTools: ["list"],
    });
    for (const name of ["wildcard", "mixed", "scalar"]) {
      assert.equal(trustedServers.has(name), false, name);
    }
    assert.deepEqual(trustedServers.get("empty"), {
      exactUrl: DOCS_URL,
      allowAll: false,
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("listed read-only tools fill only a missing readOnlyHint", () => {
  const readOnlyTools = new Set(["getPage"]);
  const decide = (
    toolName: string,
    annotations?: Record<string, boolean>,
    trusted = true,
  ) =>
    evaluateMcpPermission(toolName, annotations, trusted, false, readOnlyTools)
      .kind;

  assert.equal(decide("mcp__docs__getPage"), "allow");
  assert.equal(decide("mcp__docs__getPage", { destructiveHint: false }), "allow");
  assert.equal(decide("mcp__docs__getPage", { readOnlyHint: false }), "prompt");
  assert.equal(decide("mcp__docs__getPage", { destructiveHint: true }), "prompt");
  assert.equal(decide("mcp__docs__getPage", undefined, false), "prompt");
  assert.equal(decide("mcp__docs__getPageAndEdit"), "prompt");
  assert.equal(decide("mcp__docs__updatePage"), "prompt");
});

async function callThroughGate({
  tool,
  policy = { exactUrl: DOCS_URL, readOnlyTools: ["getPage"] },
  url = DOCS_URL,
  projectServer,
  annotations,
}: {
  tool: string;
  policy?: Record<string, unknown>;
  url?: string;
  projectServer?: Record<string, unknown>;
  annotations?: Record<string, boolean>;
}) {
  const root = mkdtempSync(join(tmpdir(), "mcp-permissions-readonly-gate-"));
  const handlers = new Map<string, (event: unknown, context: any) => unknown>();
  let prompts = 0;
  try {
    const configPath = join(root, "mcp-permissions.json");
    writeFileSync(configPath, JSON.stringify({ trustedServers: { docs: policy } }));
    mkdirSync(join(root, ".pi", "agent"), { recursive: true });
    writeFileSync(
      join(root, ".pi", "agent", "mcp.json"),
      JSON.stringify({ mcpServers: { docs: { url } } }),
    );
    const cwd = join(root, "project");
    if (projectServer) {
      mkdirSync(join(cwd, ".pi"), { recursive: true });
      writeFileSync(
        join(cwd, ".pi", "mcp.json"),
        JSON.stringify({ mcpServers: { docs: projectServer } }),
      );
    }
    const pi = {
      on(event: string, handler: (event: unknown, context: any) => unknown) {
        handlers.set(event, handler);
      },
      getMcpServers: () => [],
      getAllTools: () => [{ name: tool, annotations }],
    } as unknown as ExtensionAPI;

    registerMcpPermissions(pi, { configPath, homeDirectory: root });
    await handlers.get("session_start")?.(
      {},
      { cwd, isProjectTrusted: () => projectServer !== undefined },
    );
    const result = await handlers.get("tool_call")?.(
      { toolName: tool, input: {} },
      {
        hasUI: true,
        ui: {
          select() {
            prompts++;
            return "Deny";
          },
        },
      },
    );
    return { blocked: (result as { block?: boolean } | undefined)?.block === true, prompts };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("listed reads pass the gate only on the pinned endpoint", async () => {
  assert.deepEqual(await callThroughGate({ tool: "mcp__docs__getPage" }), {
    blocked: false,
    prompts: 0,
  });
  assert.deepEqual(
    await callThroughGate({
      tool: "mcp__docs__getPage",
      projectServer: { exposure: "deferred" },
    }),
    { blocked: false, prompts: 0 },
    "exposure-only project overrides keep the pinned endpoint",
  );
  for (const change of [
    { tool: "mcp__docs__updatePage" },
    { tool: "mcp__other__getPage" },
    { tool: "mcp__docs__getPage", annotations: { readOnlyHint: false } },
    { tool: "mcp__docs__getPage", url: "https://example.invalid/v2/mcp" },
    { tool: "mcp__docs__getPage", url: `${DOCS_URL}?proxy=1` },
    {
      tool: "mcp__docs__getPage",
      projectServer: { url: "https://example.invalid/v2/mcp" },
    },
    { tool: "mcp__docs__getPage", policy: { exactUrl: DOCS_URL } },
  ]) {
    assert.deepEqual(
      await callThroughGate(change),
      { blocked: true, prompts: 1 },
      JSON.stringify(change),
    );
  }
});
