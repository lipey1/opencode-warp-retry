import { Plugin } from "@opencode/plugin"
import { execFile } from "node:child_process"
import { appendFileSync, existsSync, mkdirSync } from "node:fs"
import { homedir } from "node:os"
import { dirname } from "node:path"

const DEFAULT_PROXY_URL = "http://127.0.0.1:40000"
const DEFAULT_RETRY_DELAY_MS = 1_000
const DEFAULT_MAX_ROTATIONS = 3
const SETTLE_MS = 1_000
const RECENT_CYCLE_MS = 5_000
const DISCONNECT_WAIT_MS = 800
const TRACE_POLL_MS = 500
const TRACE_POLL_ATTEMPTS = 20
const COMMAND_TIMEOUT_MS = 15_000
const TRACE_TIMEOUT_MS = 8_000

type Options = {
  proxyUrl?: string
  warpCli?: string
  curl?: string
  logFile?: string
  retryDelayMs?: number
  maxRotations?: number
  requireProxyEnv?: boolean
}

type Config = {
  proxyUrl: string
  warpCli: string
  curl: string
  logFile: string
  retryDelayMs: number
  maxRotations: number
}

const state = (() => {
  const key = Symbol.for("opencode.warp-retry.state")
  const global = globalThis as Record<symbol, unknown>
  if (!global[key]) {
    global[key] = {
      inFlight: null as Promise<boolean> | null,
      lastCycle: null as { attempt: number; at: number } | null,
    }
  }
  return global[key] as {
    inFlight: Promise<boolean> | null
    lastCycle: { attempt: number; at: number } | null
  }
})()

function envValue(...names: string[]) {
  for (const name of names) {
    const value = process.env[name]
    if (value) return value
  }
  return undefined
}

function numberFrom(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return undefined
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, Math.round(value)))
}

function defaultWarpCli() {
  if (process.platform === "win32") {
    const windowsPath = String.raw`C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe`
    if (existsSync(windowsPath)) return windowsPath
  }
  return "warp-cli"
}

function defaultCurl() {
  if (process.platform === "win32") {
    const windowsPath = String.raw`C:\Windows\System32\curl.exe`
    if (existsSync(windowsPath)) return windowsPath
  }
  return "curl"
}

function defaultLogFile() {
  if (process.platform === "win32" && process.env.LOCALAPPDATA) {
    return `${process.env.LOCALAPPDATA}\\opencode-warp-retry\\warp-retry.log`
  }
  return `${homedir()}/.local/share/opencode-warp-retry/warp-retry.log`
}

function resolveConfig(options: Options): Config {
  const retryDelay =
    numberFrom(options.retryDelayMs) ??
    numberFrom(envValue("WARP_RETRY_DELAY_MS")) ??
    DEFAULT_RETRY_DELAY_MS
  const maxRotations =
    numberFrom(options.maxRotations) ??
    numberFrom(envValue("WARP_RETRY_MAX_ROTATIONS")) ??
    DEFAULT_MAX_ROTATIONS

  return {
    proxyUrl: options.proxyUrl ?? envValue("WARP_RETRY_PROXY") ?? DEFAULT_PROXY_URL,
    warpCli: options.warpCli ?? envValue("WARP_RETRY_WARP_CLI") ?? defaultWarpCli(),
    curl: options.curl ?? envValue("WARP_RETRY_CURL") ?? defaultCurl(),
    logFile: options.logFile ?? envValue("WARP_RETRY_LOG") ?? defaultLogFile(),
    retryDelayMs: clamp(retryDelay, 0, 60_000),
    maxRotations: clamp(maxRotations, 1, 10),
  }
}

function log(config: Config, message: string) {
  try {
    mkdirSync(dirname(config.logFile), { recursive: true })
    appendFileSync(config.logFile, `${new Date().toISOString()}  ${message}\r\n`, "utf8")
  } catch {
    // Logging must never prevent the retry.
  }
}

function delay(ms: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, ms))
}

type RunResult = { ok: boolean; code: string | number | null; output: string }

function run(file: string, args: string[], timeout: number) {
  return new Promise<RunResult>((resolve) => {
    execFile(file, args, { timeout, windowsHide: true }, (error, stdout, stderr) => {
      const code = error ? ((error as { code?: string | number }).code ?? 1) : 0
      resolve({
        ok: !error,
        code,
        output: `${stdout ?? ""}${stderr ?? ""}`.trim(),
      })
    })
  })
}

function proxyMatches(proxyUrl: string) {
  let hostPort: string
  try {
    const url = new URL(proxyUrl)
    const port = url.port || (url.protocol === "https:" ? "443" : "80")
    hostPort = `${url.hostname}:${port}`
  } catch {
    return false
  }

  return ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"]
    .map((name) => process.env[name])
    .filter((value): value is string => Boolean(value))
    .some((value) => value.includes(hostPort))
}

async function proxyTrace(config: Config) {
  const result = await run(
    config.curl,
    ["-sS", "--max-time", "8", "--proxy", config.proxyUrl, "https://www.cloudflare.com/cdn-cgi/trace"],
    TRACE_TIMEOUT_MS,
  )
  if (!result.ok) return { ready: false, ip: null as string | null }

  const ready = /(^|\r?\n)warp=on(\r?\n|$)/i.test(result.output)
  const ip = /(^|\r?\n)ip=([^\r\n]+)/i.exec(result.output)?.[2]?.trim() ?? null
  return { ready, ip }
}

async function cycleWarp(config: Config) {
  // Remember the current egress IP so we can verify the reconnect changed it.
  const before = await proxyTrace(config)
  let previousIp = before.ip

  for (let rotation = 1; rotation <= config.maxRotations; rotation++) {
    log(
      config,
      `free usage limit reached: disconnecting WARP (rotation ${rotation}/${config.maxRotations})`,
    )
    const off = await run(config.warpCli, ["disconnect"], COMMAND_TIMEOUT_MS)
    log(config, `disconnect: ok=${off.ok} code=${off.code} ${off.output}`)

    await delay(DISCONNECT_WAIT_MS)

    log(config, "reconnecting WARP")
    const on = await run(config.warpCli, ["connect"], COMMAND_TIMEOUT_MS)
    log(config, `connect: ok=${on.ok} code=${on.code} ${on.output}`)
    if (!on.ok) {
      log(config, `warp-cli connect failed; check warpCli (${config.warpCli})`)
      return false
    }

    // The proxy answers before `warp-cli status` reports Connected.
    // Wait for the trace to confirm warp=on.
    let trace: { ready: boolean; ip: string | null } = { ready: false, ip: null }
    let waited = 0
    for (let i = 0; i < TRACE_POLL_ATTEMPTS; i++) {
      await delay(TRACE_POLL_MS)
      waited = (i + 1) * TRACE_POLL_MS
      trace = await proxyTrace(config)
      if (trace.ready) break
    }

    if (!trace.ready) {
      log(config, `WARP proxy did not return within ${(TRACE_POLL_ATTEMPTS * TRACE_POLL_MS) / 1000}s`)
      return false
    }

    // If WARP came back on the same IP and rotations remain, rotate again
    // immediately instead of spending another OpenCode retry on the same IP.
    if (previousIp && trace.ip && trace.ip === previousIp && rotation < config.maxRotations) {
      log(config, `WARP reconnected with the same IP (${trace.ip}); rotating again`)
      previousIp = trace.ip
      continue
    }

    log(
      config,
      `WARP ready after ${waited}ms; IP ${previousIp ?? "?"} -> ${trace.ip ?? "?"}; settling for ${SETTLE_MS}ms`,
    )
    await delay(SETTLE_MS)
    return true
  }

  return false
}

function ensureWarp(config: Config) {
  if (state.inFlight) {
    log(config, "WARP cycle already in progress; waiting for it")
    return state.inFlight
  }

  const task = cycleWarp(config)
    .catch((error) => {
      log(config, `WARP cycle error: ${error instanceof Error ? error.message : String(error)}`)
      return false
    })
    .finally(() => {
      state.inFlight = null
    })

  state.inFlight = task
  return task
}

function isFreeLimit(error: { type?: string; message?: unknown }) {
  return (
    error.type === "provider.free-limit" ||
    (error.type === "provider.quota" && /free usage limit/i.test(String(error.message)))
  )
}

export default Plugin.define({
  id: "warp-retry",
  async setup(ctx) {
    const options = (ctx.options ?? {}) as Options
    const config = resolveConfig(options)
    const requireProxyEnv =
      options.requireProxyEnv ?? envValue("WARP_RETRY_REQUIRE_PROXY") !== "false"

    if (requireProxyEnv && !proxyMatches(config.proxyUrl)) {
      log(
        config,
        `plugin loaded but no proxy environment matches ${config.proxyUrl}; automatic retry disabled. ` +
          "Launch OpenCode with HTTPS_PROXY/HTTP_PROXY set to the WARP proxy.",
      )
      return
    }

    log(config, `plugin loaded; automatic free-limit retry enabled (proxy: ${config.proxyUrl})`)

    await ctx.session.hook("retry", async (event) => {
      if (!isFreeLimit(event.error)) return

      // Several plugin registrations can receive the same event. If a cycle
      // just ran for this attempt (same failure wave), reuse the fresh IP.
      const recent = state.lastCycle
      if (recent && recent.attempt === event.attempt && Date.now() - recent.at < RECENT_CYCLE_MS) {
        log(
          config,
          `WARP was already rotated for attempt ${event.attempt}; reusing the fresh connection`,
        )
        event.decision = { retry: true, delay: config.retryDelayMs }
        return
      }

      // Every free-limit failure starts a new WARP rotation. OpenCode caps
      // physical attempts per request (~10), so the loop continues within
      // that cap until an IP change works.
      log(config, `free usage limit on attempt ${event.attempt}; starting a WARP rotation`)

      const ready = await ensureWarp(config)
      if (!ready) {
        log(config, "WARP did not reconnect; letting the original error surface")
        return
      }

      state.lastCycle = { attempt: event.attempt, at: Date.now() }
      event.decision = { retry: true, delay: config.retryDelayMs }
      log(config, `WARP reconnected; retrying in ${config.retryDelayMs}ms (attempt ${event.attempt})`)
    })
  },
})
