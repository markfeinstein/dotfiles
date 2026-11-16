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
