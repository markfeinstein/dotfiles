import { chmod, mkdir, rename, unlink, writeFile } from "node:fs/promises";
import { createServer, type Server, type Socket } from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const MAX_REQUEST_BYTES = 8192;
const MODEL_PICKER_PROTOCOL_VERSION = 2;
const CATALOG_REFRESH_TIMEOUT_MS = 15_000;
const PROVIDER_COLUMN_WIDTH = 12;
const BASE_MODEL_COLUMN_WIDTH = 19;
const CONTEXT_COLUMN_WIDTH = 6;
const OUTPUT_COLUMN_WIDTH = 5;
const INPUT_PRICE_COLUMN_WIDTH = 8;
const OUTPUT_PRICE_COLUMN_WIDTH = 9;
const THINKING_COLUMN_WIDTH = 8;
const IMAGE_COLUMN_WIDTH = 6;
const COLUMN_GAP = "  ";
const SEARCH_ALIAS_GAP = 96;
const THINKING_ICON = "\u{f09d1}";
const IMAGE_ICON = "\uf03e";
const THINKING_COLOR = "\x1b[96m";
const IMAGE_COLOR = "\x1b[95m";
const CURRENT_COLOR = "\x1b[92m";
const PRESET_COLOR = "\x1b[96m";
const DEFAULT_COLOR = "\x1b[93m";
const CONTEXT_WARNING_COLOR = "\x1b[91m";
const INPUT_PRICE_COLOR = "\x1b[96m";
const OUTPUT_PRICE_COLOR = "\x1b[95m";
const ANSI_DIM = "\x1b[2m";
const ANSI_CONCEAL = "\x1b[8m";
const ANSI_RESET = "\x1b[0m";
const CURRENT_MARKER = "✓";
const PRESET_MARKER = "◆";
const DEFAULT_MARKER = "★";
const GRAPHEME_SEGMENTER = new Intl.Segmenter(undefined, {
  granularity: "grapheme",
});
const GENERIC_PROVIDER_ICON = "\uec19";
const PROVIDER_ICONS: Record<string, string> = {
  github: "\uf09b",
  "github-copilot": "\uf09b",
  copilot: "\uf09b",
  openai: "\uec81",
  "openai-codex": "\uec81",
  anthropic: "\uec82",
  "claude-code": "\uec82",
};
const PROVIDER_LABELS: Record<string, string> = {
  "github-copilot": "GitHub",
  "openai-codex": "OpenAI",
  "claude-code": "Anthropic",
};
const THINKING_LEVELS = new Set([
  "off",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
]);

export type ThinkingLevel =
  "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";

export type ModelPickerScope = "all" | "scoped";
export type RefreshStatus = "current" | "ok" | "partial" | "timeout";

export interface ModelPickerChoice {
  provider: string;
  providerName: string;
  modelId: string;
  name: string;
  contextWindow: number;
  maxTokens: number;
  cost: {
    input: number;
    output: number;
  };
  reasoning: boolean;
  imageInput: boolean;
  thinkingLevel?: ThinkingLevel;
  current: boolean;
  exactPreset: boolean;
  default: boolean;
  contextOverflow: boolean;
  tieredPricing: boolean;
}

export interface ModelPickerFormatOptions {
  scope?: ModelPickerScope;
  hasScopedModels?: boolean;
  thinkingLevel?: ThinkingLevel;
  contextTokens?: number | null;
  idle?: boolean;
  refreshStatus?: RefreshStatus;
}

interface ListRequest {
  action: "list";
  scope?: ModelPickerScope;
  refresh?: boolean;
}

interface SelectRequest {
  action: "select";
  provider: string;
  modelId: string;
  thinkingLevel?: ThinkingLevel;
}

type PickerRequest = ListRequest | SelectRequest;

export interface ModelPickerServer {
  socketPath: string;
  rowsPath: string;
  refreshRows(): Promise<void>;
  close(): Promise<void>;
}

function stateHome(env: NodeJS.ProcessEnv): string {
  return env.XDG_STATE_HOME || join(env.HOME || homedir(), ".local", "state");
}

function safeBlockId(blockId: string): string {
  return blockId.replace(/^block:/, "").replace(/[^A-Za-z0-9._-]/g, "_");
}

export function modelPickerSocketPath(
  blockId: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  return join(
    stateHome(env),
    "pi",
    "model-picker",
    `${safeBlockId(blockId)}.sock`,
  );
}

export function modelPickerRowsPath(
  blockId: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  return join(
    stateHome(env),
    "pi",
    "model-picker",
    `${safeBlockId(blockId)}.tsv`,
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function parseRequest(value: unknown): PickerRequest | undefined {
  if (!isRecord(value) || typeof value.action !== "string") return;
  if (value.action === "list") {
    const allowedKeys = new Set(["action", "scope", "refresh"]);
    if (!Object.keys(value).every((key) => allowedKeys.has(key))) return;
    if (
      value.scope !== undefined &&
      value.scope !== "all" &&
      value.scope !== "scoped"
    )
      return;
    if (value.refresh !== undefined && typeof value.refresh !== "boolean")
      return;
    return {
      action: "list",
      scope: value.scope,
      refresh: value.refresh,
    };
  }
  if (
    value.action !== "select" ||
    typeof value.provider !== "string" ||
    typeof value.modelId !== "string"
  ) {
    return;
  }
  if (
    value.thinkingLevel !== undefined &&
    (typeof value.thinkingLevel !== "string" ||
      !THINKING_LEVELS.has(value.thinkingLevel))
  ) {
    return;
  }
  const allowedKeys = new Set([
    "action",
    "provider",
    "modelId",
    "thinkingLevel",
  ]);
  if (!Object.keys(value).every((key) => allowedKeys.has(key))) return;
  return {
    action: "select",
    provider: value.provider,
    modelId: value.modelId,
    thinkingLevel: value.thinkingLevel as ThinkingLevel | undefined,
  };
}

function cleanCell(value: unknown): string {
  return String(value)
    .normalize("NFC")
    .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b./g, "")
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/[\u202a-\u202e\u2066-\u2069]/g, "")
    .replace(/\s+/gu, " ")
    .trim();
}

function stripAnsi(value: string): string {
  return value.replace(/\x1b\[[0-9;]*m/g, "");
}

function isWideCodePoint(codePoint: number): boolean {
  return (
    codePoint >= 0x1100 &&
    (codePoint <= 0x115f ||
      codePoint === 0x2329 ||
      codePoint === 0x232a ||
      (codePoint >= 0x2e80 && codePoint <= 0xa4cf && codePoint !== 0x303f) ||
      (codePoint >= 0xac00 && codePoint <= 0xd7a3) ||
      (codePoint >= 0xf900 && codePoint <= 0xfaff) ||
      (codePoint >= 0xfe10 && codePoint <= 0xfe19) ||
      (codePoint >= 0xfe30 && codePoint <= 0xfe6f) ||
      (codePoint >= 0xff00 && codePoint <= 0xff60) ||
      (codePoint >= 0xffe0 && codePoint <= 0xffe6) ||
      (codePoint >= 0x1f300 && codePoint <= 0x1faff) ||
      (codePoint >= 0x20000 && codePoint <= 0x3fffd))
  );
}

function graphemes(value: string): string[] {
  return [...GRAPHEME_SEGMENTER.segment(value)].map(
    (segment) => segment.segment,
  );
}

function graphemeWidth(value: string): number {
  if (/^[\p{Mark}\u200d\ufe0e\ufe0f]+$/u.test(value)) return 0;
  if (/\p{Extended_Pictographic}|[\u{1f1e6}-\u{1f1ff}]/u.test(value)) return 2;
  const codePoint = value.codePointAt(0);
  return codePoint !== undefined && isWideCodePoint(codePoint) ? 2 : 1;
}

function visibleWidth(value: string): number {
  return graphemes(stripAnsi(value)).reduce(
    (width, grapheme) => width + graphemeWidth(grapheme),
    0,
  );
}

function truncateToWidth(value: string, width: number): string {
  if (visibleWidth(value) <= width) return value;
  const ellipsis = "…";
  const budget = Math.max(0, width - visibleWidth(ellipsis));
  let used = 0;
  let truncated = "";
  for (const grapheme of graphemes(stripAnsi(value))) {
    const nextWidth = graphemeWidth(grapheme);
    if (used + nextWidth > budget) break;
    truncated += grapheme;
    used += nextWidth;
  }
  return `${truncated}${ellipsis}`;
}

function fitColumn(
  value: string,
  width: number,
  align: "left" | "right" = "left",
): string {
  const truncated = truncateToWidth(value, width);
  const padding = " ".repeat(Math.max(0, width - visibleWidth(truncated)));
  return align === "right"
    ? `${padding}${truncated}`
    : `${truncated}${padding}`;
}

function colorColumn(value: string, color: string): string {
  return `${color}${value}${ANSI_RESET}`;
}

function dimColumn(value: string): string {
  return colorColumn(value, ANSI_DIM);
}

function normalizeProvider(provider: unknown): string {
  return cleanCell(provider)
    .trim()
    .toLowerCase()
    .replace(/[\s_]+/g, "-");
}

function providerLabel(provider: unknown, displayName: unknown): string {
  const identifier = normalizeProvider(provider);
  const configuredName = cleanCell(displayName);
  const label =
    PROVIDER_LABELS[identifier] ||
    configuredName ||
    identifier.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  return `${PROVIDER_ICONS[identifier] || GENERIC_PROVIDER_ICON} ${label}`;
}

function titleCaseModelFamily(value: string): string {
  return value
    .split(/[\s-]+/)
    .filter(Boolean)
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1).toLowerCase())
    .join(" ");
}

function compactCatalogModelName(name: string): string {
  const normalized = name.trim().replace(/^(?:OpenAI|Anthropic)\s*:\s*/i, "");
  const claudeFamilyFirst = normalized.match(
    /^Claude\s+(Opus|Sonnet|Haiku|Fable|Mythos)\s+(\d+(?:\.\d+)*)(.*)$/i,
  );
  if (claudeFamilyFirst) {
    return `${titleCaseModelFamily(claudeFamilyFirst[1])} ${claudeFamilyFirst[2]}${claudeFamilyFirst[3]}`;
  }

  const claudeVersionFirst = normalized.match(
    /^Claude\s+(\d+(?:\.\d+)*)\s+(Opus|Sonnet|Haiku|Fable|Mythos)(.*)$/i,
  );
  if (claudeVersionFirst) {
    return `${titleCaseModelFamily(claudeVersionFirst[2])} ${claudeVersionFirst[1]}${claudeVersionFirst[3]}`;
  }

  const namedGpt = normalized.match(/^GPT[- ](\d+(?:\.\d+)*)\s+(.+)$/i);
  if (namedGpt) {
    const qualifier = namedGpt[2].trim().match(/^(.*?)(\s+\([^)]*\))?$/);
    const family = titleCaseModelFamily(qualifier?.[1] || namedGpt[2]);
    return `${family} ${namedGpt[1]}${qualifier?.[2] || ""}`;
  }

  const plainGpt = normalized.match(/^GPT[- ](\d+(?:\.\d+)*)$/i);
  if (plainGpt) return `GPT ${plainGpt[1]}`;
  return normalized.startsWith("Claude ") ? normalized.slice(7) : normalized;
}

function compactModelId(modelId: unknown): string {
  const identifier = cleanCell(modelId);
  const leaf = identifier.split("/").at(-1) || identifier;
  const gpt = leaf.match(/^gpt-(\d+(?:\.\d+)*?)-(.+)$/i);
  if (gpt) {
    return `${titleCaseModelFamily(gpt[2].replace(/-\d{8}$/, ""))} ${gpt[1]}`;
  }
  const claude = leaf.match(
    /^claude-(opus|sonnet|haiku|fable|mythos)-(\d+)(?:[.-](\d+))?/i,
  );
  if (claude) {
    const version = claude[3] ? `${claude[2]}.${claude[3]}` : claude[2];
    return `${titleCaseModelFamily(claude[1])} ${version}`;
  }
  return identifier;
}

function modelFamily(model: ModelPickerChoice): string {
  const name = cleanCell(model.name).trim();
  if (
    normalizeProvider(model.provider) === "claude-code" &&
    model.modelId === "default"
  ) {
    const defaultTarget = name.match(/^Default\s*\((.+)\)$/i);
    return defaultTarget
      ? `${compactCatalogModelName(defaultTarget[1])} (default)`
      : "Default";
  }
  return name ? compactCatalogModelName(name) : compactModelId(model.modelId);
}

function compactQuantity(
  value: number,
  divisor: number,
  suffix: string,
): string {
  const scaled = value / divisor;
  for (const decimals of [2, 1, 0]) {
    const formatted = scaled
      .toFixed(decimals)
      .replace(/(\.\d*?[1-9])0+$|\.0+$/, "$1");
    const candidate = `${formatted}${suffix}`;
    if (visibleWidth(candidate) <= CONTEXT_COLUMN_WIDTH) return candidate;
  }
  return `${Math.round(scaled)}${suffix}`;
}

function formatTokens(value: number): string {
  if (!Number.isInteger(value) || value < 0) return "—";
  if (value >= 1_000_000) return compactQuantity(value, 1_000_000, "M");
  if (value >= 1_000) return compactQuantity(value, 1_000, "K");
  return String(value);
}

function formatPrice(value: number): string {
  if (!Number.isFinite(value) || value < 0) return "—";
  if (Number.isInteger(value)) return `$${value}`;
  if (value > 0 && value < 0.001) {
    return `$${value.toExponential(1).replace(".0e", "e").replace("e+", "e")}`;
  }
  const decimals = value < 0.01 ? 4 : 3;
  let formatted = value.toFixed(decimals).replace(/0+$/, "").replace(/\.$/, "");
  if ((formatted.split(".")[1] || "").length === 1) formatted += "0";
  return `$${formatted}`;
}

interface TokenCostTier {
  inputTokensAbove: number;
  input: number;
  output: number;
}

function effectiveTokenCost(
  cost: { input: number; output: number; tiers?: readonly TokenCostTier[] },
  contextTokens: number | null | undefined,
): { input: number; output: number; tiered: boolean } {
  let effective = cost;
  let threshold = -1;
  if (contextTokens != null) {
    for (const tier of cost.tiers ?? []) {
      if (
        contextTokens > tier.inputTokensAbove &&
        tier.inputTokensAbove > threshold
      ) {
        effective = tier;
        threshold = tier.inputTokensAbove;
      }
    }
  }
  return {
    input: effective.input,
    output: effective.output,
    tiered: threshold >= 0,
  };
}

function coloredIcon(icon: string, color: string): string {
  return `${color}${icon}${ANSI_RESET}`;
}

function thinkingSupport(model: ModelPickerChoice): string {
  if (!model.reasoning) return "—";
  const thinking = coloredIcon(THINKING_ICON, THINKING_COLOR);
  return model.thinkingLevel
    ? `${thinking} ${cleanCell(model.thinkingLevel)}`
    : thinking;
}

function imageSupport(model: ModelPickerChoice): string {
  return model.imageInput ? coloredIcon(IMAGE_ICON, IMAGE_COLOR) : "—";
}

interface ColumnVisibility {
  showOutput: boolean;
  showThinking: boolean;
  showImages: boolean;
  modelWidth: number;
}

function visibleColumns(models: ModelPickerChoice[]): ColumnVisibility {
  const showOutput = new Set(models.map((model) => model.maxTokens)).size > 1;
  return {
    showOutput,
    showThinking:
      new Set(models.map((model) => model.reasoning)).size > 1 ||
      models.some((model) => model.thinkingLevel !== undefined),
    showImages: new Set(models.map((model) => model.imageInput)).size > 1,
    modelWidth:
      BASE_MODEL_COLUMN_WIDTH +
      (showOutput ? 0 : OUTPUT_COLUMN_WIDTH + COLUMN_GAP.length),
  };
}

function modelHeader(models: ModelPickerChoice[]): string {
  const visibility = visibleColumns(models);
  const columns = [
    fitColumn("MODEL", visibility.modelWidth),
    fitColumn("PROVIDER", PROVIDER_COLUMN_WIDTH),
    fitColumn("CTX", CONTEXT_COLUMN_WIDTH),
  ];
  if (visibility.showOutput)
    columns.push(fitColumn("OUT", OUTPUT_COLUMN_WIDTH));
  columns.push(
    fitColumn("INPUT/M", INPUT_PRICE_COLUMN_WIDTH),
    fitColumn("OUTPUT/M", OUTPUT_PRICE_COLUMN_WIDTH),
  );
  if (visibility.showThinking)
    columns.push(fitColumn("THINKING", THINKING_COLUMN_WIDTH));
  if (visibility.showImages)
    columns.push(fitColumn("IMAGES", IMAGE_COLUMN_WIDTH));
  return `    ${columns.join(COLUMN_GAP)}`;
}

function stableIdentity(model: ModelPickerChoice): string {
  return JSON.stringify([model.provider, model.modelId]);
}

function selectionPayload(model: ModelPickerChoice): string {
  return JSON.stringify({
    action: "select",
    provider: model.provider,
    modelId: model.modelId,
    ...(model.thinkingLevel === undefined
      ? {}
      : { thinkingLevel: model.thinkingLevel }),
  });
}

function searchAliases(model: ModelPickerChoice): string {
  return cleanCell(
    [
      model.provider,
      model.modelId,
      `${model.provider}/${model.modelId}`,
      model.providerName,
      model.name,
      model.reasoning ? "reasoning thinking" : "",
      model.imageInput ? "image vision" : "",
      formatTokens(model.contextWindow),
      model.exactPreset ? "exact preset" : "",
      model.default ? "default" : "",
      model.tieredPricing ? "tiered price" : "",
    ].join(" "),
  );
}

function headerMetadata(
  options: ModelPickerFormatOptions,
  hasOverflow: boolean,
  hasTieredPricing: boolean,
): string {
  const scope = options.scope ?? "all";
  const hasScopedModels = options.hasScopedModels === true ? "1" : "0";
  const thinkingLevel = options.thinkingLevel ?? "off";
  const context =
    options.contextTokens == null ? "—" : formatTokens(options.contextTokens);
  const idle = options.idle === false ? "0" : "1";
  const refreshStatus = options.refreshStatus ?? "current";
  return `ok;protocol=${MODEL_PICKER_PROTOCOL_VERSION};cap_scope=1;cap_refresh=1;scope=${scope};scoped=${hasScopedModels};thinking=${thinkingLevel};context=${context};overflow=${hasOverflow ? "1" : "0"};tiered=${hasTieredPricing ? "1" : "0"};idle=${idle};refresh=${refreshStatus}`;
}

export function formatModelPickerTsv(
  models: ModelPickerChoice[],
  options: ModelPickerFormatOptions = {},
): string {
  if (models.length === 0)
    return pickerError("No models are available in this Pi session");
  const ordered = [...models].sort(
    (a, b) =>
      Number(b.exactPreset) - Number(a.exactPreset) ||
      Number(b.current) - Number(a.current) ||
      Number(b.default) - Number(a.default),
  );
  const visibility = visibleColumns(ordered);
  const lines = ordered.map((model) => {
    const context = fitColumn(
      `${model.contextOverflow ? "!" : ""}${formatTokens(model.contextWindow)}`,
      CONTEXT_COLUMN_WIDTH,
    );
    const columns = [
      fitColumn(modelFamily(model), visibility.modelWidth),
      dimColumn(
        fitColumn(
          providerLabel(model.provider, model.providerName),
          PROVIDER_COLUMN_WIDTH,
        ),
      ),
      model.contextOverflow
        ? colorColumn(context, CONTEXT_WARNING_COLOR)
        : context,
    ];
    if (visibility.showOutput)
      columns.push(
        fitColumn(formatTokens(model.maxTokens), OUTPUT_COLUMN_WIDTH),
      );
    columns.push(
      colorColumn(
        fitColumn(
          `${model.tieredPricing ? "↑" : ""}${formatPrice(model.cost.input)}`,
          INPUT_PRICE_COLUMN_WIDTH,
          "right",
        ),
        INPUT_PRICE_COLOR,
      ),
      colorColumn(
        fitColumn(
          formatPrice(model.cost.output),
          OUTPUT_PRICE_COLUMN_WIDTH,
          "right",
        ),
        OUTPUT_PRICE_COLOR,
      ),
    );
    if (visibility.showThinking)
      columns.push(fitColumn(thinkingSupport(model), THINKING_COLUMN_WIDTH));
    if (visibility.showImages)
      columns.push(fitColumn(imageSupport(model), IMAGE_COLUMN_WIDTH));
    const currentMarker = model.current
      ? coloredIcon(CURRENT_MARKER, CURRENT_COLOR)
      : " ";
    const presetMarker = model.exactPreset
      ? coloredIcon(PRESET_MARKER, PRESET_COLOR)
      : " ";
    const defaultMarker = model.default
      ? coloredIcon(DEFAULT_MARKER, DEFAULT_COLOR)
      : " ";
    const display = `${currentMarker}${presetMarker}${defaultMarker} ${columns.join(COLUMN_GAP)}`;
    const aliases = `${ANSI_CONCEAL}${" ".repeat(SEARCH_ALIAS_GAP)}${searchAliases(model)}${ANSI_RESET}`;
    return `${stableIdentity(model)}\t${selectionPayload(model)}\t${display}${aliases}`;
  });
  const metadata = headerMetadata(
    options,
    ordered.some((model) => model.contextOverflow),
    ordered.some((model) => model.tieredPricing),
  );
  return [`${metadata}\t\t${modelHeader(ordered)}`, ...lines].join("\n") + "\n";
}

function pickerOk(detail: string): string {
  return `ok\t${cleanCell(detail)}\n`;
}

function pickerError(message: string): string {
  return `error\t${cleanCell(message)}\n`;
}

export interface ModelPickerChoiceOptions {
  scope?: ModelPickerScope;
  defaultProvider?: string;
  defaultModel?: string;
  contextTokens?: number | null;
}

function modelKey(provider: string, modelId: string): string {
  return `${provider}\0${modelId}`;
}

export async function modelPickerChoices(
  ctx: ExtensionContext,
  options: ModelPickerChoiceOptions = {},
): Promise<ModelPickerChoice[]> {
  const available = await ctx.modelRegistry.getAvailable();
  const availableByKey = new Map(
    available.map(
      (model) => [modelKey(model.provider, model.id), model] as const,
    ),
  );
  const hasScopedModels = ctx.scopedModels.length > 0;
  const requestedScope = options.scope ?? (hasScopedModels ? "scoped" : "all");
  const scope =
    requestedScope === "scoped" && hasScopedModels ? "scoped" : "all";
  const scoped =
    scope === "scoped"
      ? ctx.scopedModels.flatMap(({ model, thinkingLevel }) => {
          const refreshed = availableByKey.get(
            modelKey(model.provider, model.id),
          );
          return refreshed ? [{ model: refreshed, thinkingLevel }] : [];
        })
      : available.map((model) => ({ model, thinkingLevel: undefined }));

  return scoped.map(({ model, thinkingLevel }) => {
    const current =
      ctx.model?.provider === model.provider && ctx.model?.id === model.id;
    const cost = effectiveTokenCost(model.cost, options.contextTokens);
    return {
      provider: model.provider,
      providerName: ctx.modelRegistry.getProviderDisplayName(model.provider),
      modelId: model.id,
      name: model.name || model.id,
      contextWindow: model.contextWindow,
      maxTokens: model.maxTokens,
      cost: {
        input: cost.input,
        output: cost.output,
      },
      reasoning: model.reasoning,
      imageInput: model.input.includes("image"),
      thinkingLevel,
      current,
      exactPreset:
        current &&
        thinkingLevel !== undefined &&
        thinkingLevel === ctx.thinkingLevel,
      default:
        options.defaultProvider === model.provider &&
        options.defaultModel === model.id,
      contextOverflow:
        options.contextTokens != null &&
        options.contextTokens > model.contextWindow,
      tieredPricing: cost.tiered,
    };
  });
}

async function refreshCatalog(ctx: ExtensionContext): Promise<RefreshStatus> {
  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, CATALOG_REFRESH_TIMEOUT_MS);
  try {
    const result = await ctx.modelRegistry.refresh({
      force: true,
      signal: controller.signal,
    });
    if (timedOut || result.aborted) return "timeout";
    return result.errors.size > 0 ? "partial" : "ok";
  } catch {
    return timedOut ? "timeout" : "partial";
  } finally {
    clearTimeout(timeout);
  }
}

async function modelPickerDocument(
  pi: ExtensionAPI,
  ctx: ExtensionContext,
  request: ListRequest = { action: "list" },
): Promise<string> {
  const refreshStatus = request.refresh ? await refreshCatalog(ctx) : "current";
  const hasScopedModels = ctx.scopedModels.length > 0;
  const requestedScope = request.scope ?? (hasScopedModels ? "scoped" : "all");
  let scope: ModelPickerScope =
    requestedScope === "scoped" && hasScopedModels ? "scoped" : "all";
  const settings = pi.getSettings();
  const contextTokens = ctx.getContextUsage()?.tokens;
  let choices = await modelPickerChoices(ctx, {
    scope,
    defaultProvider: settings.defaultProvider,
    defaultModel: settings.defaultModel,
    contextTokens,
  });
  if (scope === "scoped" && choices.length === 0) {
    scope = "all";
    choices = await modelPickerChoices(ctx, {
      scope,
      defaultProvider: settings.defaultProvider,
      defaultModel: settings.defaultModel,
      contextTokens,
    });
  }
  return formatModelPickerTsv(choices, {
    scope,
    hasScopedModels,
    thinkingLevel: ctx.thinkingLevel,
    contextTokens,
    idle: ctx.isIdle(),
    refreshStatus,
  });
}

async function handleRequest(
  pi: ExtensionAPI,
  getContext: () => ExtensionContext | undefined,
  request: PickerRequest,
): Promise<string> {
  const ctx = getContext();
  if (!ctx) return pickerError("Pi session is unavailable");

  if (request.action === "list") return modelPickerDocument(pi, ctx, request);
  if (!ctx.isIdle()) return pickerError("Pi is busy");

  const choices = await modelPickerChoices(ctx, { scope: "all" });
  const choice = choices.find(
    (candidate) =>
      candidate.provider === request.provider &&
      candidate.modelId === request.modelId,
  );
  if (!choice) return pickerError("Model is not available in this session");
  if (request.thinkingLevel !== undefined) {
    const pinned = ctx.scopedModels.find(
      (candidate) =>
        candidate.model.provider === request.provider &&
        candidate.model.id === request.modelId &&
        candidate.thinkingLevel === request.thinkingLevel,
    );
    if (!pinned)
      return pickerError("Thinking level is not available for this model");
  }

  const model = ctx.modelRegistry.find(choice.provider, choice.modelId);
  if (!model) return pickerError("Model disappeared from the registry");
  if (!(await pi.setModel(model))) {
    return pickerError(
      `No authentication for ${choice.provider}/${choice.modelId}`,
    );
  }
  if (request.thinkingLevel !== undefined)
    pi.setThinkingLevel(request.thinkingLevel);

  const selected = cleanCell(`${choice.provider}/${choice.modelId}`);
  ctx.ui.notify(`Model: ${selected}`, "info");
  return pickerOk(selected);
}

async function removePath(path: string): Promise<void> {
  try {
    await unlink(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

let rowsTempSequence = 0;

async function writeRowsFile(path: string, rows: string): Promise<void> {
  const temporaryPath = `${path}.${process.pid}.${(rowsTempSequence += 1)}.tmp`;
  try {
    await writeFile(temporaryPath, rows, { mode: 0o600 });
    await rename(temporaryPath, path);
    await chmod(path, 0o600);
  } finally {
    await removePath(temporaryPath);
  }
}

function writeResponse(socket: Socket, response: string): void {
  socket.end(response);
}

export async function startModelPickerServer(
  pi: ExtensionAPI,
  getContext: () => ExtensionContext | undefined,
  blockId: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<ModelPickerServer> {
  const socketPath = modelPickerSocketPath(blockId, env);
  const rowsPath = modelPickerRowsPath(blockId, env);
  await mkdir(dirname(socketPath), { recursive: true, mode: 0o700 });
  await chmod(dirname(socketPath), 0o700);
  await removePath(socketPath);
  await removePath(rowsPath);

  let closed = false;
  let refreshQueue = Promise.resolve();
  const refreshRows = (): Promise<void> => {
    if (closed) return refreshQueue;
    refreshQueue = refreshQueue
      .catch(() => {})
      .then(async () => {
        if (closed) return;
        const ctx = getContext();
        if (!ctx) throw new Error("Pi session is unavailable");
        await writeRowsFile(rowsPath, await modelPickerDocument(pi, ctx));
      });
    return refreshQueue;
  };
  await refreshRows();

  const sockets = new Set<Socket>();
  const server: Server = createServer((socket) => {
    sockets.add(socket);
    socket.setEncoding("utf8");
    socket.setTimeout(CATALOG_REFRESH_TIMEOUT_MS + 5_000, () =>
      socket.destroy(),
    );
    socket.on("close", () => sockets.delete(socket));
    socket.on("error", () => {});

    let buffer = "";
    let handled = false;
    socket.on("data", (chunk: string) => {
      if (handled) return;
      buffer += chunk;
      if (Buffer.byteLength(buffer) > MAX_REQUEST_BYTES) {
        handled = true;
        writeResponse(socket, pickerError("Request is too large"));
        return;
      }
      const newline = buffer.indexOf("\n");
      if (newline < 0) return;
      handled = true;

      let parsed: unknown;
      try {
        parsed = JSON.parse(buffer.slice(0, newline));
      } catch {
        writeResponse(socket, pickerError("Invalid JSON request"));
        return;
      }
      const request = parseRequest(parsed);
      if (!request) {
        writeResponse(socket, pickerError("Invalid model-picker request"));
        return;
      }
      void handleRequest(pi, getContext, request)
        .then((response) => writeResponse(socket, response))
        .catch((error) => {
          writeResponse(
            socket,
            pickerError(error instanceof Error ? error.message : String(error)),
          );
        });
    });
  });

  server.on("error", () => {
    // Runtime server errors must not terminate the Pi process.
  });
  try {
    await new Promise<void>((resolve, reject) => {
      const onError = (error: Error): void => {
        server.off("listening", onListening);
        reject(error);
      };
      const onListening = (): void => {
        server.off("error", onError);
        resolve();
      };
      server.once("error", onError);
      server.once("listening", onListening);
      server.listen(socketPath);
    });
    await chmod(socketPath, 0o600);
  } catch (error) {
    closed = true;
    for (const socket of sockets) socket.destroy();
    if (server.listening)
      await new Promise<void>((resolve) => server.close(() => resolve()));
    await removePath(socketPath);
    await removePath(rowsPath);
    throw error;
  }

  return {
    socketPath,
    rowsPath,
    refreshRows,
    async close(): Promise<void> {
      if (closed) return;
      closed = true;
      await refreshQueue.catch(() => {});
      for (const socket of sockets) socket.destroy();
      await new Promise<void>((resolve) => server.close(() => resolve()));
      await removePath(socketPath);
      await removePath(rowsPath);
    },
  };
}

export default function rexModelPicker(pi: ExtensionAPI) {
  let activeContext: ExtensionContext | undefined;
  let pickerServer: ModelPickerServer | undefined;

  pi.on("session_start", async (_event, ctx) => {
    activeContext = ctx;
    const blockId = process.env.REX_BLOCK;
    if (ctx.mode !== "tui" || !blockId) return;

    try {
      pickerServer = await startModelPickerServer(
        pi,
        () => activeContext,
        blockId,
      );
    } catch (error) {
      ctx.ui.notify(
        `Rex model picker unavailable: ${error instanceof Error ? error.message : String(error)}`,
        "warning",
      );
    }
  });

  const refreshPickerRows = (ctx: ExtensionContext): void => {
    void pickerServer?.refreshRows().catch((error) => {
      ctx.ui.notify(
        `Rex model picker cache unavailable: ${error instanceof Error ? error.message : String(error)}`,
        "warning",
      );
    });
  };

  pi.on("model_select", (_event, ctx) => {
    activeContext = ctx;
    refreshPickerRows(ctx);
  });
  pi.on("thinking_level_select", (_event, ctx) => {
    activeContext = ctx;
    refreshPickerRows(ctx);
  });

  pi.on("session_shutdown", async () => {
    activeContext = undefined;
    await pickerServer?.close();
    pickerServer = undefined;
  });
}
