# OpenClaw 2026.4.15 — Browser Tool & Plugin API Research

**Date:** 2026-04-27
**Target version:** OpenClaw 2026.4.15 (commit 041266a)
**VM:** `crux-land-ctrl` (us-central1-a)
**Method:** Direct inspection of `/usr/lib/node_modules/openclaw/` (mostly minified but with preserved string literals + a complete `dist/plugin-sdk/src/**/*.d.ts` tree shipping in the npm package), plus live CLI runs against the gateway.

Each finding below is tagged:
- **[VERIFIED]** — confirmed by file:line OR live SSH command transcript on the VM
- **[DOCUMENTED]** — appears in shipped `.d.ts` types or plugin manifests but not exercised live
- **[UNVERIFIED]** — inferred from code; not exercised; flagged as a gap

---

## §1 Browser tool architecture

### What the browser tool actually is

**[VERIFIED]** OpenClaw's `browser` tool is implemented as **two cooperating processes plus a localhost HTTP bridge**:

1. **A bridge HTTP server** that exposes ~70 routes (`/screenshot`, `/navigate`, `/click`, `/snapshot`, `/trace/start`, `/trace/stop`, etc.) on a loopback port.
   - Source: `/usr/lib/node_modules/openclaw/dist/bridge-server-BMEyg4Hw.js:35` — `startBrowserBridgeServer(...)` builds an Express app bound to `127.0.0.1:<port>` (default `0` → kernel-assigned). Auth required (`authToken` or `authPassword`); routes installed via `registerBrowserRoutes(app, ...)`.
   - All ~70 routes listed at `/usr/lib/node_modules/openclaw/dist/server-context-qgfDaRbE.js` lines 662–3397. Examples:
     - `app.post("/screenshot", …)` line 2220
     - `app.post("/trace/start", …)` line 1772
     - `app.post("/trace/stop", …)` line 1799
     - `app.post("/navigate", …)` line 2139
     - `app.get("/snapshot", …)` line 2290

2. **Playwright-core** as the actual browser driver, not raw CDP.
   - `/usr/lib/node_modules/openclaw/node_modules/playwright-core` (verified `ls`)
   - `/usr/lib/node_modules/openclaw/dist/pw-ai-BJRFEth4.js` line ~1: `import { chromium, devices } from "playwright-core";`
   - All `*ViaPlaywright` functions live in `pw-ai-BJRFEth4.js`: `navigateViaPlaywright`, `screenshotWithLabelsViaPlaywright`, `traceStartViaPlaywright`, `traceStopViaPlaywright`, etc. (export list at line 2389.)

3. **Chromium**, started locally OR attached to via CDP.
   - `chromium.connectOverCDP(endpoint, ...)` is the attach path (`pw-ai-BJRFEth4.js`).
   - The `browser.executablePath` and `browser.attachOnly` config keys (see §3) decide whether OpenClaw spawns its own Chromium or attaches to an existing one.
   - Chromium executable resolution: `/usr/lib/node_modules/openclaw/dist/chrome.executables-WqX45Anh.js` (handles macOS / Linux variants, including Brave/Edge/Chromium).

### How the agent's `browser` tool maps to the bridge

**[VERIFIED]** A single agent-facing tool named **`browser`** with an `action` parameter that routes to a bridge route.
- Tool definition: `/usr/lib/node_modules/openclaw/dist/plugin-service-BY9Z-wOO.js:574`:
  ```js
  function createBrowserTool(opts) { … return {
      label: "Browser",
      name: "browser",
      description: "Control the browser via OpenClaw's browser control server (status/start/stop/profiles/tabs/open/snapshot/screenshot/actions). …",
      parameters: BrowserToolSchema,
      execute: async (_toolCallId, args) => { … switch on args.action … } }; }
  ```
- Inside `execute(...)`, `params.action === "screenshot"` → POST `/screenshot` on the bridge → bridge returns `{ ok: true, path: <abs path> }` → tool returns `imageResultFromFile({ label: "browser:screenshot", path: result.path })`. (lines 740–760.)
- Other action values: `navigate`, `click`, `type`, `snapshot`, `act`, `pdf`, `evaluate`, `wait`, etc.

So **there is one tool, `browser`, with sub-actions.** There is no `browser_screenshot` separate tool.

### Bridge server lifecycle

**[VERIFIED]** The bridge server is started and managed by the OpenClaw gateway when the browser plugin loads. The gateway is the systemd-managed long-running process. The bridge listens on a port published into config state as `resolved.controlPort` (`bridge-server-BMEyg4Hw.js:84`). Authentication is required at the route level — the agent tool resolves the token via the gateway's loaded config.

### Top-level CLI surface (also goes to the same bridge)

**[VERIFIED]** The browser plugin registers a top-level `openclaw browser` command via `api.registerCli({ commands: ["browser"] })` (`plugin-registration-BcGLyuNL.js:18`). After the plugin is enabled, `openclaw browser --help` shows:
```
Commands:
  click, close, console, cookies, create-profile, delete-profile, dialog, download,
  drag, errors, evaluate, fill, focus, highlight, hover, navigate, open, pdf, press,
  profiles, requests, reset-profile, resize, responsebody, screenshot, scrollintoview,
  select, set, snapshot, start, status, stop, trace, type, ...
```
**The CLI is NOT visible in `openclaw --help` until the plugin is loaded** (i.e., a valid config + the gateway/CLI startup path that registers plugin CLIs eagerly). In the VM's previous broken state (invalid config), `openclaw browser` did not appear.

### What's still unknown

- Whether the agent tool can be told to use a remote bridge (it can — `nodeTarget` resolution at `plugin-service-BY9Z-wOO.js:600+`), but I did not exercise it.
- Whether the bridge has any built-in HAR endpoint. Search returned NONE (`grep -rE "HAR|recordHar|saveAs.*har" /usr/lib/node_modules/openclaw/dist/` finds nothing). The bridge has `GET /requests` (returns recent network requests) at `server-context-qgfDaRbE.js:1747`, but it's a query against an in-memory log, not a HAR file.

---

## §2 Plugin extension API

### Hook names — **REAL, EXACT NAMES**

**[VERIFIED]** From `/usr/lib/node_modules/openclaw/dist/plugin-sdk/src/plugins/hook-types.d.ts:29`:

```ts
export type PluginHookName =
  "before_model_resolve" | "before_prompt_build" | "before_agent_start"
  | "before_agent_reply" | "llm_input" | "llm_output" | "agent_end"
  | "before_compaction" | "after_compaction" | "before_reset"
  | "inbound_claim" | "message_received" | "message_sending" | "message_sent"
  | "before_tool_call" | "after_tool_call" | "tool_result_persist"
  | "before_message_write" | "session_start" | "session_end"
  | "subagent_spawning" | "subagent_delivery_target" | "subagent_spawned" | "subagent_ended"
  | "gateway_start" | "gateway_stop"
  | "before_dispatch" | "reply_dispatch" | "before_install";
```

Both `before_tool_call` and `after_tool_call` **are real**. The earlier subagent's claim that those names don't exist was wrong; the existing telemetry plugin's fork uses them correctly (see `~/.openclaw/plugins/openclaw-telemetry/index.ts` lines 90 + 119: `api.on("before_tool_call", ...)` / `api.on("after_tool_call", ...)`).

### Hook payload shapes

**[DOCUMENTED]** From `hook-types.d.ts` lines 130–166:
```ts
export type PluginHookBeforeToolCallEvent = {
  toolName: string;
  params: Record<string, unknown>;
  runId?: string;
  toolCallId?: string;
};
export type PluginHookBeforeToolCallResult = {
  params?: Record<string, unknown>;       // can mutate params
  block?: boolean;                        // can block the call
  blockReason?: string;
  requireApproval?: { …human-in-the-loop… };
};
export type PluginHookAfterToolCallEvent = {
  toolName: string;
  params: Record<string, unknown>;
  runId?: string;
  toolCallId?: string;
  result?: unknown;       // !! contains the bridge's return payload, e.g. { ok, path, targetId, url }
  error?: string;
  durationMs?: number;
};
export type PluginHookToolContext = {
  agentId?: string; sessionKey?: string; sessionId?: string; runId?: string;
  toolName: string; toolCallId?: string;
};
```

So inside `after_tool_call` for `toolName === "browser"`, `event.result` is the JSON returned by the bridge (e.g. for `action=screenshot`, it's the `{ ok, path, targetId, url }` object). **`event.params.action`** distinguishes which sub-action was invoked.

### Plugin registration API surface

**[DOCUMENTED]** From `/usr/lib/node_modules/openclaw/dist/plugin-sdk/src/plugins/types.d.ts:1538-1656`:

```ts
export type OpenClawPluginApi = {
  config: OpenClawConfig;
  pluginConfig?: Record<string, unknown>;     // <-- where the plugin's per-entry config arrives
  runtime: PluginRuntime;
  logger: PluginLogger;
  registerTool: (tool, opts?) => void;
  registerHook: (events, handler, opts?) => void;
  registerHttpRoute: (params) => void;
  registerCli: (registrar, opts?) => void;
  registerService: (svc) => void;
  registerGatewayMethod: (method, handler, opts?) => void;
  // … many provider/channel registers …
  on: <K extends PluginHookName>(hookName: K, handler: PluginHookHandlerMap[K], opts?: { priority?: number }) => void;
};

export type OpenClawPluginDefinition = {
  id: string;
  name?: string;
  description?: string;
  register?: (api: OpenClawPluginApi) => void | Promise<void>;
  activate?: (api: OpenClawPluginApi) => void | Promise<void>;
};
```

### Install mechanism

**[VERIFIED]** Live `openclaw plugins install --help`:
```
openclaw plugins install [options] <path-or-spec-or-plugin>

Arguments:
  path-or-spec-or-plugin   Path (.ts/.js/.zip/.tgz/.tar.gz), npm package spec, or marketplace plugin name

Options:
  --dangerously-force-unsafe-install    Bypass dangerous-code install blocking
  --force                               Overwrite existing
  -l, --link                            Link a local path instead of copying
  --marketplace <source>                Install a Claude marketplace plugin from a local repo/path or git/GitHub
  --pin                                 Record npm installs as exact name@version
```

**[VERIFIED]** Successful install of the existing telemetry plugin via:
```
$ openclaw plugins install /home/zidong/.openclaw/plugins/openclaw-telemetry --link
Linked plugin path: ~/.openclaw/plugins/openclaw-telemetry
Restart the gateway to load plugins.
```

After install:
- `plugins.installs.<id>.source = "path"` (or `"npm"`, `"archive"`, `"clawhub"`, `"marketplace"` — see schema.)
- `plugins.load.paths` gets the path appended.
- `plugins.entries.<id>.enabled = true`/`false` toggles loading.

**`plugins.entries.<id>.path` is NOT a valid key** — that's part of why the existing config fails validation. The path is recorded in `plugins.installs.<id>.installPath` and `plugins.load.paths`, both managed by the install command, not hand-written.

### `plugins.entries.<id>` config shape

**[VERIFIED]** From `openclaw config schema` output:
```jsonc
"plugins.entries.<any string>": {
  "enabled": boolean,
  "hooks": { "allowPromptInjection": boolean },
  "subagent": { "allowModelOverride": boolean, "allowedModels": [string] },
  "config": { /* plugin-defined; constrained by the plugin's own configSchema in openclaw.plugin.json */ }
}
// additionalProperties: false
```

Real-world example, `~/.openclaw/plugins/openclaw-telemetry/openclaw.plugin.json` declares its `configSchema` with:
- `enabled: boolean`
- `filePath: string`
- `syslog: { enabled, host, port, protocol, facility, appName, format }`
- `redact: { enabled, patterns, replacement }`
- `integrity: { enabled, algorithm }`
- `rateLimit: { enabled, maxEventsPerSecond, burstSize }`
- `rotate: { enabled, maxSizeBytes, maxFiles, compress }`

So `plugins.entries.telemetry.config.redactSecrets = true` is **NOT** valid (no such key in the plugin's manifest schema). The right shape is `plugins.entries.telemetry.config.redact = { enabled: true }`. The `openclaw plugins install` CLI rejected the invalid config explicitly:
```
[plugins] telemetry invalid config: <root>: must NOT have additional properties
```

For comparison, official plugin `brave` (`/usr/lib/node_modules/openclaw/dist/extensions/brave/openclaw.plugin.json`) shows the canonical shape:
```jsonc
{
  "id": "brave",
  "providerAuthEnvVars": { "brave": ["BRAVE_API_KEY"] },
  "uiHints": { … },
  "contracts": { "webSearchProviders": ["brave"] },
  "configSchema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
      "webSearch": { "type": "object", … "properties": { "apiKey": { "type": ["string","object"] } } }
    }
  }
}
```
And it's set in user config via `plugins.entries.brave.config.webSearch.apiKey = "…"`.

---

## §3 Browser config schema

### Browser config lives at TOP-LEVEL `browser`, not under `tools`

**[VERIFIED]** `openclaw config schema` shows `tools.*` accepts only:
- `tools.profile` (`"minimal"|"coding"|"messaging"|"full"`)
- `tools.allow` / `tools.alsoAllow` / `tools.deny` (`string[]`)
- `tools.byProvider` (per-provider variants)
- `tools.web.search.*` (web-search-specific)

**`tools.browser` is NOT in the schema.** The current `provision_controller.sh:133-145` block is invalid — that's the actual root cause of `tools: Unrecognized key: "browser"`.

The real browser config lives at top level:

```jsonc
"browser": {
  "enabled": boolean,
  "evaluateEnabled": boolean,
  "cdpUrl": string,                              // attach to existing CDP
  "remoteCdpTimeoutMs": int,
  "remoteCdpHandshakeTimeoutMs": int,
  "color": string,
  "executablePath": string,                      // explicit Chromium path
  "headless": boolean,
  "noSandbox": boolean,
  "attachOnly": boolean,                         // skip local launch
  "cdpPortRangeStart": int,
  "defaultProfile": string,
  "snapshotDefaults": { "mode": "efficient" },   // currently the only allowed value
  "ssrfPolicy": {
    "dangerouslyAllowPrivateNetwork": boolean,
    "allowedHostnames": string[],
    "hostnameAllowlist": string[]
  },
  "profiles": {
    "<profile-name>": {                          // pattern: ^[a-z0-9-]+$
      "cdpPort": int,
      "cdpUrl": string,
      "userDataDir": string,
      "driver": "openclaw" | "clawd" | "existing-session",
      "attachOnly": boolean,
      "color": string                            // required, pattern: ^#?[0-9a-fA-F]{6}$
    }
  },
  "extraArgs": string[]
}
// additionalProperties: false
```

### Recording / trace keys in browser schema?

**[VERIFIED]** `browser.trace`, `browser.recording`, `browser.har`, `browser.video`, `browser.profileDir`, `browser.captureScreenshots`, `browser.captureNetwork`, `browser.captureConsole`, `browser.outputDir` — **NONE exist in the schema.**

So the entire `tools.browser.trace.*` block in `provision_controller.sh:133-145` is hallucinated configuration. It's read by the existing telemetry plugin (which `readFileSync`s the JSON directly and bypasses schema validation; see `~/.openclaw/plugins/openclaw-telemetry/index.ts:39`), but the gateway's schema validator rejects the whole config and refuses to start.

### Environment variable knobs

**[VERIFIED]** Searching the dist: `OPENCLAW_BROWSER_*`, `BROWSER_TRACE`, `BROWSER_RECORD` — none. The few env vars the browser layer respects are:
- `OPENCLAW_CONTAINER` (top-level CLI)
- `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH` (paths, not browser-specific)
- `NO_PROXY`-style proxy bypass for CDP (`withNoProxyForCdpUrl` in `pw-ai-BJRFEth4.js`)

There is no `OPENCLAW_TRACE` / `OPENCLAW_BROWSER_RECORD` style toggle.

---

## §4 Existing recording surfaces

### A. Screenshots are auto-persisted to disk

**[VERIFIED]** Every `browser.action=screenshot` call goes through `saveBrowserMediaResponse` → `saveMediaBuffer(buf, contentType, "browser", maxBytes)` (`server-context-qgfDaRbE.js:2107-2114`).

Storage path: `<resolveConfigDir()>/media/browser/<id>.<ext>` per `/usr/lib/node_modules/openclaw/dist/store-CFeRgpZO.js:21`:
```js
const resolveMediaDir = () => path.join(resolveConfigDir(), "media");
```
Default config dir is `~/.openclaw/`, so screenshots land at **`~/.openclaw/media/browser/<id>.png`** (or `.jpg`).

The bridge's response `{ ok, path }` returns the absolute path; the agent tool wraps it as a `media://` reference. **Retention** is via `cleanOldMedia` (`store-CFeRgpZO.js:r as cleanOldMedia`, line ~114) — runs periodically on a max-bytes / max-age basis.

**Implication:** If we want a screenshot trail of every CRUX-Windows run, the screenshots **already exist on disk**. We just need to (a) capture the `path` from the bridge response in our telemetry, and (b) copy/move them to a run-specific dir before retention sweeps them.

### B. Network requests are buffered in-memory

**[VERIFIED]** Bridge route `GET /requests` (`server-context-qgfDaRbE.js:1747`) returns recently-recorded requests. Backed by Playwright's `request`/`response` events, ring-buffered per profile context. **Not** persisted to disk by default — gone when the page closes.

### C. Console messages are buffered in-memory

**[VERIFIED]** `GET /console` (`server-context-qgfDaRbE.js:1701`), same pattern as `/requests`.

### D. Page errors are buffered in-memory

**[VERIFIED]** `GET /errors` (`server-context-qgfDaRbE.js:1724`).

### E. **Playwright traces** (the killer feature)

**[VERIFIED]** Real, working, first-class:
- HTTP route: `POST /trace/start` and `POST /trace/stop` (`server-context-qgfDaRbE.js:1772-1827`)
- Top-level CLI: `openclaw browser trace start` / `openclaw browser trace stop --out <path>` — confirmed live with `--help`:
  ```
  $ openclaw browser trace start --help
  Options:
    --no-screenshots   Disable screenshots
    --no-snapshots     Disable snapshots
    --sources          Include sources (bigger traces)
    --target-id <id>   CDP target id (or unique prefix)
  $ openclaw browser trace stop --help
  Options:
    --out <path>       Output path within openclaw temp dir (e.g. trace.zip or /tmp/openclaw/trace.zip)
    --target-id <id>   CDP target id (or unique prefix)
  ```
- Implementation: `pw-ai-BJRFEth4.js:2361-2383`:
  ```js
  await context.tracing.start({
    screenshots: opts.screenshots ?? true,
    snapshots: opts.snapshots ?? true,
    sources: opts.sources ?? false
  });
  …
  await context.tracing.stop({ path: tempPath });
  ```
- Output: a single `.zip` Playwright trace file containing screenshots, DOM snapshots, network log, and console — viewable in `npx playwright show-trace`. **Single-file artifact, not a directory.**
- Default trace dir: `DEFAULT_TRACE_DIR = DEFAULT_BROWSER_TMP_DIR` = `resolvePreferredOpenClawTmpDir()` (typically `/tmp/openclaw/`, `utils-DSPbCLVw.js:21`). The user can pass an explicit `--out` / `path` parameter.
- **Concurrency limit:** ONE trace per browser context at a time. Attempting `traceStart` while one is active throws `"Trace already running. Stop the current trace before starting a new one."` (`pw-ai-BJRFEth4.js:2364`).

**Important caveats vs. the previous broken plugin:**
1. The CLI flag `--output-dir` does **NOT** exist. Only `--no-screenshots`, `--no-snapshots`, `--sources`, `--target-id`. (Confirmed live: `error: unknown option '--output-dir'`.)
2. The output goes to the path passed to `--out` on STOP, not on START.
3. There is **no** `--no-network` or `--no-console` flag. Network and console are not separately gated.
4. No `--screenshot-delay-ms` flag.
5. The trace is a **`.zip` file**, not a directory. The previous wrapper expected `trace.cdp.json + screenshots/` inside a directory; that's wrong.

### F. PDF / download artifacts

**[VERIFIED]** `POST /pdf` (line 2193) writes to a path; `POST /download` writes to `DEFAULT_DOWNLOAD_DIR = /tmp/openclaw/downloads/` (`utils-DSPbCLVw.js:22`).

---

## §5 Hook points for browser observability

### From the agent's tool-call layer

**[VERIFIED]** A plugin can intercept:
- `before_tool_call` — sees `{ toolName: "browser", params: { action: "screenshot", … } }` BEFORE the bridge call. Can mutate `params`, block the call, or require operator approval.
- `after_tool_call` — sees `{ toolName, params, result, error, durationMs }` AFTER the bridge call. `result` is the bridge's response payload. **Cannot mutate** the result returned to the LLM (the type signature returns `void`, not a result object) — only observe.
- `tool_result_persist` — fires when the result is written into the agent's session messages. Can replace the message: `{ message?: AgentMessage }`.

So a plugin can:
- See every `browser.screenshot` call, including the resulting `path` field on the saved screenshot.
- Wrap a `browser.navigate` in `before_tool_call` (start trace) and `after_tool_call` (stop trace) — exactly the strategy the existing fork attempts, but with the wrong CLI flags.
- Capture per-call latency (`durationMs`).

### What a plugin CANNOT directly intercept

- **Page-level Playwright events** (`page.on("response", …)`, `page.on("console", …)`, `page.on("framenavigated", …)`). These fire inside the bridge process, in the Playwright context. The plugin runs in the agent runtime, not the bridge runtime. **No public hook is exposed for these in-process events.**
- **CDP raw protocol traffic.** No hook.
- **Playwright tracing API events.** The trace is opaque until `trace.stop` produces a zip.

### HTTP route registration as a side door

**[DOCUMENTED]** `OpenClawPluginApi.registerHttpRoute(...)` (types.d.ts:1559) and `registerService(...)` exist. A plugin **could** register a sidecar HTTP listener and inject a Playwright `chromium.connectOverCDP(url)` against the same Chromium that the bridge uses — but that requires knowing the bridge's CDP URL (resolvable via `browser.cdpUrl` config or runtime state). That's a path to in-process Playwright observability, but it competes for the single Playwright context per profile and would need careful coordination.

---

## §6 Existing browser-recording plugins

### First-party (bundled in `dist/extensions/`)

**[VERIFIED]** `ls /usr/lib/node_modules/openclaw/dist/extensions/`:

- **`browser`** — the browser tool itself (CDP/Playwright bridge). Not a recording plugin.
- **`diagnostics-otel`** — OpenTelemetry exporter. Top-level config under `diagnostics.otel.*`. Exports gateway traces/metrics/logs to an OTLP endpoint. **Does not capture browser tool internals.** Manifest configSchema is empty (`{}`); all knobs live under `diagnostics.otel.*` in the main schema (verified, confirmed by `jq ".properties.diagnostics.otel" /tmp/schema.json`).
- 96 other extensions: chat channels (slack, discord, signal, …), model providers (anthropic, openai, …), web search (brave, exa, tavily, …), media (elevenlabs, deepgram, …), memory (lancedb, wiki, …). **None are browser-recording plugins.**

### Marketplace

**[VERIFIED]** `openclaw plugins marketplace list <source>` requires a local Claude marketplace path or a git/GitHub URL. There is **no central first-party OpenClaw plugin registry** queryable by the CLI. Each user/org points to their own marketplace source.

### Third-party in-tree

**[VERIFIED]** The only browser-recording-adjacent plugin found is the existing `getnenai/openclaw-telemetry` fork at `~/.openclaw/plugins/openclaw-telemetry/`. As confirmed in §3 + §4-E, its `browser_trace.ts` wrapper calls a hallucinated CLI flag set (`--output-dir`, `--no-network`, `--no-console`, `--screenshot-delay-ms`, `--screenshots`/`--no-screenshots` are real but the rest are not), and assumes the trace is a directory rather than a `.zip` file. **It will fail at runtime** every time it tries to start a trace.

---

## §7 Recommended approaches for adding browser recording

Ranked by feasibility (fastest → hardest), with verified surfaces.

### A. Use OpenClaw's first-class `browser trace start/stop` correctly **[RECOMMENDED]**

**Surface used:** Existing Playwright tracing via `POST /trace/start` + `POST /trace/stop`, exposed via the agent's `browser` tool already (action sub-name unconfirmed; the CLI subcommand is verified). Wrapped from a plugin's `before_tool_call` / `after_tool_call` hooks.

**Code we'd write:**
- A telemetry plugin that, on `before_tool_call` for `toolName==="browser"`:
  - Issues an HTTP `POST` directly to the bridge `/trace/start` (we have `pluginConfig` and `api.config.browser.cdpUrl`/auth from the runtime). OR shells out to `openclaw browser trace start` (no flags needed for default behavior).
- On `after_tool_call`: `POST /trace/stop` with an `--out` path of `~/.openclaw/logs/run-traces/<runId>/<toolCallId>.zip`. Annotate via `tool_result_persist` (or just emit our own `tool.end.browser_trace` JSONL row pointing at the zip).
- Coordinate the per-context single-trace constraint: serialize start/stop pairs through a per-profile mutex (the existing fork does this correctly).

**Cost:** ~half a day. The hook plumbing already works in the existing fork; we just need to fix the wrapper to call the real CLI flags / HTTP routes.

**What it gives us:** Full Playwright `.zip` traces — screenshots, DOM, network, console — viewable in the Playwright Trace Viewer. This is the gold standard for browser recording.

**Risk:** One trace per browser context. If the agent runs concurrent browser actions in a single context (e.g. via `act` batched ops), some sub-actions won't be wrapped. Acceptable for CRUX-Windows where the agent serializes browser ops.

### B. Capture the screenshots that already exist + log network/console snapshots

**Surface used:** The bridge ALREADY persists screenshots to `~/.openclaw/media/browser/<id>.png` on every `browser.screenshot` call. Plus `GET /requests` and `GET /console` give in-memory snapshots.

**Code we'd write:**
- `after_tool_call` plugin: when `toolName==="browser"` AND `params.action==="screenshot"`, copy `event.result.path` to a run-specific dir and JSONL-log the path.
- Optionally: at the same hook, `fetch(`${bridge}/requests?clear=true`)` and `…/console?clear=true` and dump them to JSONL. Each browser action becomes a tuple `(action, params, screenshot_path?, requests_since_last, console_since_last)`.

**Cost:** ~2-4 hours. Essentially the existing telemetry plugin's tool.start/tool.end pattern, plus an extra fetch on each browser tool call.

**What it gives us:** A frame-by-frame screenshot trail (every time the agent calls `browser.screenshot`, which it does after most actions in CRUX-Windows runs) + per-action network/console deltas. Not as rich as Playwright traces (no DOM snapshots between screenshots), but cheap and deterministic.

**Risk:** Relies on the agent voluntarily calling `browser.screenshot`. If the agent does a `browser.click` and never screenshots, we have no visual evidence between screenshots.

### C. Combine A + B for redundancy

**Cost:** ~1 day. Most of A; B becomes free at that point (the screenshots are already there, just JSONL-log the path).

**What it gives us:** Belt-and-suspenders — Playwright trace as the rich artifact; dumped screenshot paths as a fast-skim index for humans browsing the run output.

### D. Patch OpenClaw to call Playwright tracing on every browser call automatically

**Surface used:** Modify `/usr/lib/node_modules/openclaw/dist/server-context-qgfDaRbE.js` to wrap every action in a tracing context.

**Cost:** 2-3 days, plus maintenance against every `openclaw update` minor.

**Why it's not feasible without forking:** The dist files are minified; identifiers are mostly preserved but we'd need a sed-or-AST-patch step at provision time. AND the tracing API is per-context, so a per-action wrap would require careful state management. **Don't do this** — option A achieves the same outcome through documented hooks.

### E. Build a sidecar that attaches its own Playwright client over CDP

**Surface used:** `chromium.connectOverCDP(browser.cdpUrl)` from a plugin process. Listen to `page.on("response")`, `page.on("framenavigated")`, etc. directly.

**Cost:** ~3-5 days. Needs to compete for the same Chromium target with the bridge's existing client; CDP only allows one tracing session at a time, so this conflicts with option A. Browser auto-shutdown coordination is fragile.

**Recommendation:** Skip unless we need observability that A+B don't provide (e.g. inter-action DOM diffs not captured by tracing).

### **Recommended path: A + B together (option C).**

Spend ~1 day rewriting the existing `getnenai/openclaw-telemetry` `browser_trace.ts` to:
1. Drop the bogus `--output-dir`, `--no-network`, `--no-console`, `--screenshot-delay-ms`, `--screenshots` (the explicit `--screenshots` is also not a flag — only `--no-screenshots` is) flags.
2. Use `--no-screenshots` / `--no-snapshots` / `--sources` per actual CLI.
3. Pass `--out <run-dir>/<toolCallId>.zip` on `stop`.
4. Treat the result as a `.zip` file, not a directory.
5. As a bonus, also capture `event.result.path` in `after_tool_call` for screenshot actions and JSONL-log it.

Plus fix the gateway config so the plugin actually loads (see §8).

---

## §8 What's broken right now in `provision_controller.sh` step 7

### Bad keys in the JSON

The block at `provision_controller.sh:118-148` writes:
```jsonc
{
  "plugins": {
    "entries": {
      "telemetry": {
        "enabled": true,
        "path": "${TELEMETRY_DIR}",                           // ❌ INVALID
        "config": {
          "enabled": true,
          "filePath": "${HOME}/.openclaw/logs/telemetry.jsonl",
          "redactSecrets": true                                // ❌ INVALID
        }
      }
    }
  },
  "tools": {
    "browser": {                                               // ❌ INVALID — entire block
      "trace": { … }
    }
  }
}
```

**Errors:**

1. **`plugins.entries.telemetry.path`** — not in the schema. `plugins.entries.<id>` allows only `enabled`, `hooks`, `subagent`, `config`. The plugin install path is auto-recorded under `plugins.installs.<id>.installPath` and `plugins.load.paths` by `openclaw plugins install --link <dir>`.

2. **`plugins.entries.telemetry.config.redactSecrets`** — not in the telemetry plugin's manifest configSchema. Use `redact: { enabled: true }` instead.

3. **`tools.browser.*`** — `tools` allows only `profile`, `allow`, `alsoAllow`, `deny`, `byProvider`, `web`. Browser config goes at top-level `browser`. **And `browser.trace.*` does NOT exist as a config block at all.** It was never a real OpenClaw config surface; the existing plugin reads it directly via `readFileSync` and bypasses validation.

### What to remove

Delete the entire `tools` block and the `path` key on the telemetry entry. Replace `redactSecrets` with the proper `redact` shape. Resulting valid config:
```jsonc
{
  "plugins": {
    "entries": {
      "telemetry": {
        "enabled": true,
        "config": {
          "enabled": true,
          "filePath": "${HOME}/.openclaw/logs/telemetry.jsonl",
          "redact": { "enabled": true }
        }
      }
    }
  }
}
```
This validates: `Config valid: ~/.openclaw/openclaw.json`.

### What to add to install the plugin

Replace the manual JSON write with the install command (after writing a minimal valid base config):

```bash
# After cloning $TELEMETRY_DIR
openclaw plugins install "$TELEMETRY_DIR" --link
# This will:
#   - append plugins.load.paths += [$TELEMETRY_DIR]
#   - set plugins.installs.telemetry = { source: "path", installPath, version, installedAt }
#   - leave plugins.entries.telemetry alone (caller writes that for config knobs)
```

**Verified live:**
```
$ openclaw plugins install /home/zidong/.openclaw/plugins/openclaw-telemetry --link
Linked plugin path: ~/.openclaw/plugins/openclaw-telemetry
Restart the gateway to load plugins.
$ openclaw plugins list | grep telemetry
│ @openclaw/   │ telemetr │ openclaw │ loaded   │ ~/.openclaw/plugins/openclaw-telemetry/index.ts          │ 0.1.0     │
```

After install, `openclaw browser --help` works (the browser plugin's CLI registers when the plugin loader runs successfully on startup).

### What ELSE is broken in the existing telemetry fork (orthogonal to config)

Even with config fixed, the plugin's `browser_trace.ts` (lines 110–148) calls `openclaw browser trace start --output-dir <dir> --no-screenshots --no-network --no-console --screenshot-delay-ms 250`. **None of `--output-dir`, `--no-network`, `--no-console`, `--screenshot-delay-ms` are valid flags.** Verified live:
```
$ openclaw browser trace start --output-dir /tmp/test-trace --no-screenshots
error: unknown option '--output-dir'
```

That plugin will fail every time the gateway invokes it. The telemetry JSONL events for tool start/end will still write (they're separate code paths), but `browserTracePath` will always be `null` and `browserTraceError` will always be set. **This is fixable in the plugin, not in OpenClaw.** See §7 option A for what the wrapper should look like.

---

## Quick reference — verified citations

| Claim | File:Line |
|---|---|
| Browser tool uses Playwright over CDP | `pw-ai-BJRFEth4.js:1` (`import { chromium } from "playwright-core"`) |
| Bridge server is Express on 127.0.0.1 | `bridge-server-BMEyg4Hw.js:35-86` |
| `app.post("/trace/start", …)` real route | `server-context-qgfDaRbE.js:1772` |
| `traceStartViaPlaywright(...)` real impl | `pw-ai-BJRFEth4.js:2361-2370` |
| Hook names list authoritative | `plugin-sdk/src/plugins/hook-types.d.ts:29` |
| `before_tool_call`/`after_tool_call` types | `plugin-sdk/src/plugins/hook-types.d.ts:130-166` |
| Plugin API surface | `plugin-sdk/src/plugins/types.d.ts:1538-1657` |
| `api.on(hookName, handler)` signature | `plugin-sdk/src/plugins/types.d.ts:1654` |
| `tools.*` schema (no `browser`) | `openclaw config schema → .properties.tools` |
| Top-level `browser.*` schema | `openclaw config schema → .properties.browser` |
| `plugins.entries.<id>` schema | `openclaw config schema → .properties.plugins.entries` |
| Screenshots saved to `~/.openclaw/media/browser/` | `store-CFeRgpZO.js:21` (`resolveMediaDir`), `server-context-qgfDaRbE.js:2107-2114` |
| `openclaw browser trace start` real CLI | live `openclaw browser trace start --help` |
| `--output-dir` flag is hallucinated | live `error: unknown option '--output-dir'` |
| Existing telemetry plugin fork | `~/.openclaw/plugins/openclaw-telemetry/index.ts` + `src/browser_trace.ts` |
