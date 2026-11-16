import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type {
  ExtensionAPI,
  RegisteredMcpServer,
  ToolAnnotations as PiToolAnnotations,
} from "@earendil-works/pi-coding-agent";

export type ToolAnnotations = PiToolAnnotations;

type PermissionDecision =
  { kind: "allow" } | { kind: "prompt"; reason: string };

type OAuthPolicy = {
  callbackUrl: string;
  clientId: string;
  clientName: string;
};

type LoopbackPortArgument = { loopbackPort: true };
type TrustedServerPolicy = {
  allowAll: boolean;
} & (
  | {
      exactUrl: string;
      oauth?: OAuthPolicy;
    }
  | {
      exactCommand: string;
      exactArgs: ReadonlyArray<string | LoopbackPortArgument>;
    }
);

type TrustedServer = {
  allowAll: boolean;
};

type PermissionConfig = {
  trustedServers: ReadonlyMap<string, TrustedServerPolicy>;
};

type PermissionOptions = {
  configPath?: string;
  homeDirectory?: string;
  resolveTrustedServers?: (
    cwd: string,
    projectTrusted: boolean,
  ) => ReadonlyMap<string, TrustedServer>;
};

const CONFIG_FILE = "mcp-permissions.json";
const SERVER_NAME = /^[A-Za-z0-9_-]+$/;
const MCP_EXPOSURES = new Set([
  "codemode",
  "codemode-deferred",
  "deferred",
  "direct",
  "hidden",
]);
const MAX_APPROVAL_FIELDS = 12;
const MAX_APPROVAL_VALUE_LENGTH = 160;
const APPROVAL_FIELD_NAMES = new Set([
  "app_id",
  "area_id",
  "automation_id",
  "category_id",
  "config_key",
  "dashboard_id",
  "device_id",
  "domain",
  "entity_id",
  "floor_id",
  "helper_id",
  "label_id",
  "operation_id",
  "resource_id",
  "scene_id",
  "script_id",
  "service",
  "url_path",
]);
const PRIVACY_SENSITIVE_TOOL_NAMES = new Set(["ha_get_camera_image"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isExposure(value: unknown): boolean {
  return typeof value === "string" && MCP_EXPOSURES.has(value);
}

function isOptional(
  value: unknown,
  predicate: (candidate: unknown) => boolean,
): boolean {
  return value === undefined || predicate(value);
}

function normalizedServerName(value: string): string {
  return value.replace(/-/g, "_");
}

function normalizedEndpointUrl(endpoint: URL): string | undefined {
  if (endpoint.search || endpoint.hash) return;
  const pathname = endpoint.pathname.replace(/\/+$/, "");
  if (!pathname) return;
  return `${endpoint.origin}${pathname}`;
}

function parseOAuthPolicy(value: unknown): OAuthPolicy | undefined {
  if (!isRecord(value)) return;
  const callbackUrl = value.callbackUrl;
  const clientId = value.clientId;
  const clientName = value.clientName;
  if (
    Object.keys(value).length !== 3 ||
    typeof callbackUrl !== "string" ||
    typeof clientId !== "string" ||
    typeof clientName !== "string"
  ) {
    return;
  }
  return { callbackUrl, clientId, clientName };
}

function parseLoopbackPortArgument(
  value: unknown,
): LoopbackPortArgument | undefined {
  if (
    !isRecord(value) ||
    Object.keys(value).length !== 1 ||
    value.loopbackPort !== true
  ) {
    return;
  }
  return { loopbackPort: true };
}

function parseExactArgs(
  value: unknown,
): ReadonlyArray<string | LoopbackPortArgument> | undefined {
  if (!Array.isArray(value)) return;
  const parsed: Array<string | LoopbackPortArgument> = [];
  for (const argument of value) {
    if (typeof argument === "string") parsed.push(argument);
    else {
      const loopback = parseLoopbackPortArgument(argument);
      if (!loopback) return;
      parsed.push(loopback);
    }
  }
  return parsed;
}

export function readPermissionConfig(path: string): PermissionConfig {
  try {
    const document: unknown = JSON.parse(
      readFileSync(path, "utf8").replace(/^\uFEFF/, ""),
    );
    if (!isRecord(document) || !isRecord(document.trustedServers)) {
      return { trustedServers: new Map() };
    }
    const trustedServers = new Map<string, TrustedServerPolicy>();
    for (const [name, value] of Object.entries(document.trustedServers)) {
      if (!SERVER_NAME.test(name) || !isRecord(value)) continue;
      const allowAll = value.allowAll === true;
      if (value.allowAll !== undefined && typeof value.allowAll !== "boolean")
        continue;

      if (typeof value.exactUrl === "string") {
        if (!URL.canParse(value.exactUrl)) continue;
        const endpoint = new URL(value.exactUrl);
        const exactUrl = normalizedEndpointUrl(endpoint);
        if (
          !exactUrl ||
          endpoint.protocol !== "https:" ||
          endpoint.username ||
          endpoint.password
        )
          continue;
        const oauth =
          value.oauth === undefined ? undefined : parseOAuthPolicy(value.oauth);
        if (value.oauth !== undefined && oauth === undefined) continue;
        if (
          !Object.keys(value).every(
            (key) =>
              key === "exactUrl" || key === "oauth" || key === "allowAll",
          )
        )
          continue;
        trustedServers.set(normalizedServerName(name), {
          exactUrl,
          ...(oauth ? { oauth } : {}),
          allowAll,
        });
        continue;
      }

      const exactArgs = parseExactArgs(value.exactArgs);
      if (
        typeof value.exactCommand !== "string" ||
        !value.exactCommand.startsWith("/") ||
        exactArgs === undefined ||
        !Object.keys(value).every(
          (key) =>
            key === "exactCommand" || key === "exactArgs" || key === "allowAll",
        )
      )
        continue;
      trustedServers.set(normalizedServerName(name), {
        exactCommand: value.exactCommand,
        exactArgs,
        allowAll,
      });
    }
    return { trustedServers };
  } catch {
    return { trustedServers: new Map() };
  }
}

function readMcpServer(
  path: string,
  normalizedName: string,
): Record<string, unknown> | undefined {
  try {
    const document: unknown = JSON.parse(
      readFileSync(path, "utf8").replace(/^\uFEFF/, ""),
    );
    if (!isRecord(document) || !isRecord(document.mcpServers)) return;
    for (const [name, value] of Object.entries(document.mcpServers)) {
      if (
        SERVER_NAME.test(name) &&
        normalizedServerName(name) === normalizedName &&
        isRecord(value)
      ) {
        return value;
      }
    }
  } catch {
    return;
  }
  return;
}

function oauthMatches(
  value: unknown,
  expected: OAuthPolicy | undefined,
): boolean {
  if (expected === undefined) return value === undefined;
  const actual = parseOAuthPolicy(value);
  return (
    actual !== undefined &&
    actual.callbackUrl === expected.callbackUrl &&
    actual.clientId === expected.clientId &&
    actual.clientName === expected.clientName
  );
}

function commonConfigMatches(config: Record<string, unknown>): boolean {
  return (
    isOptional(config.exposure, isExposure) &&
    isOptional(
      config.toolExposure,
      (value) => isRecord(value) && Object.values(value).every(isExposure),
    ) &&
    isOptional(config.enabled, (value) => typeof value === "boolean") &&
    isOptional(config.description, (value) => typeof value === "string") &&
    isOptional(
      config.timeout,
      (value) => typeof value === "number" && value > 0,
    )
  );
}

function loopbackPortArgumentMatches(value: string): boolean {
  const match = /^(?:127\.0\.0\.1|localhost|\[::1\]):([0-9]+)$/.exec(value);
  if (!match) return false;
  const port = Number(match[1]);
  return Number.isInteger(port) && port >= 1 && port <= 65535;
}

function exactArgsMatch(
  actual: unknown,
  expected: ReadonlyArray<string | LoopbackPortArgument>,
): boolean {
  if (!Array.isArray(actual) || actual.length !== expected.length) return false;
  return expected.every((argument, index) =>
    typeof argument === "string"
      ? actual[index] === argument
      : typeof actual[index] === "string" &&
        loopbackPortArgumentMatches(actual[index]),
  );
}

function endpointMatches(
  config: Record<string, unknown> | undefined,
  policy: TrustedServerPolicy,
): boolean {
  if (!config || !commonConfigMatches(config)) return false;
  if ("exactUrl" in policy) {
    if (typeof config.url !== "string" || !URL.canParse(config.url))
      return false;
    if (
      !isOptional(
        config.type,
        (value) => value === "http" || value === "streamable-http",
      ) ||
      config.headers !== undefined ||
      config.auth !== undefined ||
      !oauthMatches(config.oauth, policy.oauth)
    ) {
      return false;
    }
    const endpoint = new URL(config.url);
    return (
      endpoint.protocol === "https:" &&
      !endpoint.username &&
      !endpoint.password &&
      normalizedEndpointUrl(endpoint) === policy.exactUrl
    );
  }

  return (
    isOptional(config.type, (value) => value === "stdio") &&
    config.command === policy.exactCommand &&
    exactArgsMatch(config.args ?? [], policy.exactArgs) &&
    isOptional(
      config.env,
      (value) => isRecord(value) && Object.keys(value).length === 0,
    ) &&
    config.cwd === undefined &&
    config.url === undefined &&
    config.headers === undefined &&
    config.oauth === undefined &&
    config.auth === undefined
  );
}

export function resolveTrustedServers(
  homeDirectory: string,
  cwd: string,
  projectTrusted: boolean,
  policies: ReadonlyMap<string, TrustedServerPolicy>,
  registeredServers: readonly RegisteredMcpServer[] = [],
): Map<string, TrustedServer> {
  const trusted = new Map<string, TrustedServer>();
  const userConfigPath = join(homeDirectory, ".pi", "agent", "mcp.json");
  const projectConfigPath = join(cwd, ".pi", "mcp.json");

  for (const [serverName, policy] of policies) {
    const projectConfig = projectTrusted
      ? readMcpServer(projectConfigPath, serverName)
      : undefined;
    const projectDefinesEndpoint =
      projectConfig !== undefined &&
      ["url", "command", "type"].some((key) => key in projectConfig);
    const userConfig = readMcpServer(userConfigPath, serverName);
    const registeredConfig = registeredServers.find(
      (server) => normalizedServerName(server.name) === serverName,
    )?.config as Record<string, unknown> | undefined;
    const selected = projectDefinesEndpoint
      ? projectConfig
      : userConfig ?? registeredConfig;
    if (endpointMatches(selected, policy)) {
      trusted.set(serverName, { allowAll: policy.allowAll });
    }
  }
  return trusted;
}

export function parseNativeMcpToolName(
  toolName: string,
): { serverName: string; originalToolName: string } | undefined {
  if (!toolName.startsWith("mcp__")) return;
  const remainder = toolName.slice("mcp__".length);
  const separator = remainder.indexOf("__");
  if (separator <= 0 || separator === remainder.length - 2) return;
  return {
    serverName: normalizedServerName(remainder.slice(0, separator)),
    originalToolName: remainder.slice(separator + 2),
  };
}

export function evaluateMcpPermission(
  toolName: string,
  annotations: ToolAnnotations | undefined,
  serverTrusted: boolean,
  allowAll = false,
): PermissionDecision {
  const call = parseNativeMcpToolName(toolName);
  if (!call) return { kind: "allow" };
  if (!serverTrusted)
    return { kind: "prompt", reason: "MCP server identity is not pinned" };
  if (allowAll) return { kind: "allow" };
  if (PRIVACY_SENSITIVE_TOOL_NAMES.has(call.originalToolName)) {
    return {
      kind: "prompt",
      reason: "Privacy-sensitive MCP read requires confirmation",
    };
  }
  if (annotations?.destructiveHint === true) {
    return { kind: "prompt", reason: "MCP tool declares destructive behavior" };
  }
  if (annotations?.readOnlyHint === true) return { kind: "allow" };
  return {
    kind: "prompt",
    reason: "MCP call is not declared a non-destructive read",
  };
}

function renderApprovalValue(value: unknown): string | undefined {
  if (typeof value === "string") {
    const normalized = value.replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
    if (!normalized || normalized.length > MAX_APPROVAL_VALUE_LENGTH) return;
    return JSON.stringify(normalized);
  }
  if (typeof value === "boolean") return String(value);
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (Array.isArray(value) && value.length <= 8) {
    const rendered = value.map(renderApprovalValue);
    if (rendered.some((entry) => entry === undefined)) return;
    const joined = `[${rendered.join(", ")}]`;
    if (joined.length <= MAX_APPROVAL_VALUE_LENGTH) return joined;
  }
  return;
}

function collectApprovalFields(
  value: unknown,
  prefix = "",
  depth = 0,
  result: string[] = [],
): string[] {
  if (depth > 4 || result.length >= MAX_APPROVAL_FIELDS || !isRecord(value))
    return result;
  for (const [key, entry] of Object.entries(value)) {
    if (result.length >= MAX_APPROVAL_FIELDS) break;
    const path = prefix ? `${prefix}.${key}` : key;
    const rendered = APPROVAL_FIELD_NAMES.has(key.toLowerCase())
      ? renderApprovalValue(entry)
      : undefined;
    if (rendered !== undefined) result.push(`${path}: ${rendered}`);
    else if (isRecord(entry))
      collectApprovalFields(entry, path, depth + 1, result);
  }
  return result;
}

export function formatMcpApprovalSummary(label: string, args: unknown): string {
  const fields = collectApprovalFields(args);
  return fields.length === 0
    ? `${label}\nRequest argument values are hidden because this tool has no approved safe summary fields.`
    : `${label}\nRequest scope:\n${fields.map((field) => `- ${field}`).join("\n")}\nOther argument values are hidden.`;
}

export function registerMcpPermissions(
  pi: ExtensionAPI,
  options: PermissionOptions = {},
): void {
  const homeDirectory = options.homeDirectory ?? homedir();
  const configPath =
    options.configPath ??
    join(homeDirectory, ".pi", "agent", "extensions", CONFIG_FILE);
  let trustedServers = new Map<string, TrustedServer>();

  pi.on("session_start", (_event, ctx) => {
    trustedServers = new Map(
      options.resolveTrustedServers?.(ctx.cwd, ctx.isProjectTrusted()) ??
        resolveTrustedServers(
          homeDirectory,
          ctx.cwd,
          ctx.isProjectTrusted(),
          readPermissionConfig(configPath).trustedServers,
          pi.getMcpServers(),
        ),
    );
  });

  pi.on("tool_call", async (event, ctx) => {
    const call = parseNativeMcpToolName(event.toolName);
    if (!call) return;
    const annotations = pi
      .getAllTools()
      .find((tool) => tool.name === event.toolName)?.annotations;
    const trust = trustedServers.get(call.serverName);
    const decision = evaluateMcpPermission(
      event.toolName,
      annotations,
      trust !== undefined,
      trust?.allowAll,
    );
    if (decision.kind === "allow") return;
    if (!ctx.hasUI) {
      return {
        block: true,
        reason: `MCP call blocked (no UI to confirm): ${decision.reason}`,
      };
    }

    const summary = formatMcpApprovalSummary(
      `${call.serverName}/${call.originalToolName}`,
      event.input,
    );
    const selection = await ctx.ui.select(
      `MCP permission required: ${decision.reason}\n${summary}`,
      ["Allow once", "Deny", "Decline and stop"],
    );
    if (selection === "Allow once") return;
    if (selection === "Decline and stop") {
      ctx.abort();
      return { block: true, reason: "User declined and stopped MCP call" };
    }
    return { block: true, reason: "User denied MCP call" };
  });
}

export default function mcpPermissions(pi: ExtensionAPI): void {
  registerMcpPermissions(pi);
}
