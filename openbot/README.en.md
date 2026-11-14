# OpenBot + opencode-warp-retry (ACP)

[OpenBot](https://github.com/nightly-labs/openbot) runs OpenCode as an **ACP agent**. It starts the OpenCode CLI in a process of its own, talks over `stdin`/`stdout` (Agent Client Protocol), and keeps that process as long as it needs it — OpenBot may restart it over time.

That is a separate path from OpenCode Desktop:

- the process inherits the **OpenBot environment**, not your terminal's;
- launching OpenCode Desktop with a proxy does **not** configure the OpenBot ACP process;
- without `HTTPS_PROXY`/`HTTP_PROXY`/`ALL_PROXY` in that process, the `warp-retry` plugin loads **disabled**.

The [`opencode.cmd`](opencode.cmd) wrapper fixes this: it isolates OpenBot's data, guarantees the WARP proxy, and logs the decision — without writing anything to `stdout`, which belongs to ACP.

## How OpenBot starts OpenCode

```text
OpenBot
  └─ cmd.exe /c "<folder>\opencode.cmd" acp
       └─ opencode-cli.exe acp
            └─ private ACP server (stdin/stdout)
```

OpenBot resolves the CLI in this order:

1. `OPENBOT_OPENCODE_PATH`, when you set it (recommended);
2. the managed copy OpenBot downloads itself, when present;
3. `opencode` on `PATH` (through `where.exe`), accepting `.exe`, `.cmd`, and `.bat`.

The wrapper takes that `opencode` slot. It forwards every argument, so `opencode.cmd acp` becomes `opencode-cli.exe acp`.

## What the wrapper does

1. **Isolates data and state.** It points `XDG_DATA_HOME` and `XDG_STATE_HOME` at an OpenBot-only folder. Configuration (`~/.config/opencode`) stays shared, so the plugin, MCP servers, providers, and skills are the same as in OpenCode Desktop.
2. **Guarantees the WARP proxy.** It probes the proxy for real (`https://www.cloudflare.com/cdn-cgi/trace` must answer `warp=on`). If the proxy is down, it runs `warp-cli connect` and probes again for up to ~10 s. Only then does it set `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY`.
3. **Logs the decision** to `<OPENBOT_OC_HOME>\state\warp-wrapper.log`.

For `--version` (used by OpenBot while resolving the provider, with a 10 s limit), the wrapper **skips** the WARP probe and starts the CLI immediately. A version check needs no network.

## Requirements

- Windows 10/11. For Linux/macOS, see the section at the end.
- OpenBot with the **OpenCode** provider selected.
- The OpenCode CLI installed (the `opencode-cli.exe` OpenBot uses).
- Cloudflare WARP installed, signed in, and in **proxy mode**.
- The `opencode-warp-retry` plugin installed once.

## Step by step

### 1. Install the plugin (once)

```sh
opencode plugin add opencode-warp-retry
```

The wrapper does not set `XDG_CONFIG_HOME`, so this installation also applies to OpenBot. Do not copy `src/index.ts` by hand if you already used `opencode plugin add`.

### 2. Put WARP in proxy mode

```powershell
& "C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" mode proxy
& "C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" connect
```

Confirm the proxy answers:

```powershell
curl.exe -x http://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace
```

The output must contain `warp=on`. If your proxy uses another port, adjust `WARP_PROXY_URL` in the configuration section.

### 3. Copy the wrapper to a folder of your own

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\bin" | Out-Null
Copy-Item .\openbot\opencode.cmd "$env:USERPROFILE\bin\opencode.cmd"
```

Any folder works; `%USERPROFILE%\bin` is just the suggestion used in these examples. Avoid a folder with `&` or `%` in its name.

### 4. Point OpenBot at the wrapper

The most reliable way is the `OPENBOT_OPENCODE_PATH` variable:

```powershell
[Environment]::SetEnvironmentVariable(
  "OPENBOT_OPENCODE_PATH",
  "$env:USERPROFILE\bin\opencode.cmd",
  "User"
)
```

Quit OpenBot completely and start it again. Environment variables are read only when the process starts.

**Alternative: `PATH`.** Put the wrapper's folder before the other `opencode` entries:

```powershell
$dir = "$env:USERPROFILE\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ';') -notcontains $dir) {
  [Environment]::SetEnvironmentVariable("Path", "$dir;$userPath", "User")
}
```

Restart OpenBot afterwards. `OPENBOT_OPENCODE_PATH` is better because OpenBot may also download a managed OpenCode copy; the explicit path is tried before it.

### 5. Confirm everything is wired up

Run the wrapper the way OpenBot would:

```powershell
& "$env:USERPROFILE\bin\opencode.cmd" debug paths
```

The output should show:

```text
data       C:\Users\<you>\AppData\Local\OpenBot\opencode-cli\data\opencode
config     C:\Users\<you>\.config\opencode
state      C:\Users\<you>\AppData\Local\OpenBot\opencode-cli\state\opencode
```

Isolated `data`/`state` and a shared `config` is exactly what you want.

Then send a message in OpenBot and check the plugin log:

```powershell
Get-Content "$env:LOCALAPPDATA\opencode-warp-retry\warp-retry.log" -Tail 5
```

The line must be:

```text
plugin loaded; automatic free-limit retry enabled (proxy: http://127.0.0.1:40000)
```

If you see `plugin loaded but no proxy environment matches`, the wrapper was not used or WARP was down when the ACP process started.

## Configuration

Every variable is optional and belongs in the user environment (or in the current session, for testing).

| Variable | Default | Purpose |
|---|---|---|
| `OPENBOT_OC_HOME` | `%LOCALAPPDATA%\OpenBot\opencode-cli` | Base folder for OpenBot's OpenCode `data` and `state` |
| `OPENBOT_OC_CLI` | auto | Full path to `opencode-cli.exe` |
| `WARP_PROXY_URL` | `http://127.0.0.1:40000` | WARP proxy URL |
| `WARP_AUTOCONNECT` | `1` | `0` stops the wrapper from running `warp-cli connect` |

Example with different paths:

```powershell
[Environment]::SetEnvironmentVariable("OPENBOT_OC_HOME", "D:\OpenBot\opencode-cli", "User")
[Environment]::SetEnvironmentVariable("OPENBOT_OC_CLI", "$env:LOCALAPPDATA\Programs\ai.opencode.desktop\resources\opencode-cli.exe", "User")
```

## Where sessions live (and how to move them)

By default, the wrapper uses:

```text
%LOCALAPPDATA%\OpenBot\opencode-cli\
  data\
    opencode\
      opencode.db          <- OpenBot's sessions and messages
      log\opencode.log     <- OpenBot's OpenCode log
      repos\
      shell\
      ...
  state\
    opencode\              <- OpenBot's OpenCode state
    warp-wrapper.log       <- wrapper decisions
```

To move it, set `OPENBOT_OC_HOME` and restart OpenBot:

```powershell
[Environment]::SetEnvironmentVariable("OPENBOT_OC_HOME", "D:\OpenBot\opencode-cli", "User")
```

The wrapper creates `data` and `state` at the destination. **Existing sessions are not migrated automatically.** To keep the history, close OpenBot and copy the old folder before changing the variable:

```powershell
Copy-Item "$env:LOCALAPPDATA\OpenBot\opencode-cli" "D:\OpenBot\opencode-cli" -Recurse
```

To start clean, point it at a new, empty folder.

Important notes:

- **Do not** point OpenBot at OpenCode Desktop's data folder. Both would then share sessions, logs, and the same SQLite database; the isolation exists to prevent that mix.
- `~/.config/opencode` stays shared on purpose. That is what makes the plugin, MCP servers, and providers apply to both.
- The cache (`~/.cache/opencode`) is shared too; plugins are not downloaded twice.
- `opencode.db` belongs to OpenBot's OpenCode. OpenBot's own database (`%APPDATA%\OpenBot\openbot.db`) is untouched.

## The proxy in detail

The wrapper sets these variables only in the OpenCode process:

| Variable | Value |
|---|---|
| `HTTP_PROXY` | `WARP_PROXY_URL` |
| `HTTPS_PROXY` | `WARP_PROXY_URL` |
| `ALL_PROXY` | `WARP_PROXY_URL` |
| `NO_PROXY` | `localhost,127.0.0.1,::1` |

`NO_PROXY` matters: without it, OpenCode would send even local MCP traffic (for example `127.0.0.1:3000`) through WARP.

The plugin **does not test connectivity**; it only checks whether a proxy variable matches `proxyUrl`. The wrapper does the test. If WARP is down when the ACP process starts:

1. the wrapper runs `warp-cli connect`;
2. it probes again for up to ~10 s;
3. if it still fails, it starts **without a proxy** and logs `WARP is unavailable; starting without proxy (retry disabled)`;
4. the plugin loads disabled **in that process**. A new OpenBot process/session tries again.

If WARP drops **mid-turn**, the error is usually `provider.transport` (network), not `provider.free-limit`. The current plugin only reacts to the free limit; it does not reconnect WARP on a transport failure.

## Logs

| Log | Path |
|---|---|
| Wrapper decisions | `%OPENBOT_OC_HOME%\state\warp-wrapper.log` |
| Plugin (retry/rotation) | `%LOCALAPPDATA%\opencode-warp-retry\warp-retry.log` |
| OpenBot's OpenCode | `%OPENBOT_OC_HOME%\data\opencode\log\opencode.log` |

Wrapper example:

```text
13/11/2026 21:06:50,79 [cli="C:\Users\you\AppData\Local\Programs\ai.opencode.desktop\resources\opencode-cli.exe"]
13/11/2026 21:06:50,90 [proxy WARP is up (http://127.0.0.1:40000)]
```

Plugin example when the limit hits:

```text
free usage limit on attempt 2; starting a WARP rotation
free usage limit reached: disconnecting WARP (rotation 1/3)
connect: ok=true code=0 Success
WARP ready after 500ms; IP 2a09:bac5:... -> 2a09:bac1:...; settling for 1000ms
WARP reconnected; retrying in 1000ms (attempt 2)
```

Follow it live:

```powershell
Get-Content "$env:LOCALAPPDATA\opencode-warp-retry\warp-retry.log" -Tail 20 -Wait
```

## Quick verification

```powershell
# 1. Does the wrapper answer and isolate the paths?
& "$env:USERPROFILE\bin\opencode.cmd" debug paths

# 2. Is WARP in proxy mode and connected?
& "C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" status
curl.exe -x http://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace

# 3. Is OpenBot using the wrapper?
Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
  Where-Object { $_.CommandLine -match 'opencode' } |
  Select-Object ProcessId, CommandLine
```

In step 3, `CommandLine` should show the wrapper path, not `opencode-cli.exe` directly.

## Troubleshooting

| Symptom | What to do |
|---|---|
| `opencode-cli.exe not found` on stderr | Set `OPENBOT_OC_CLI` to the CLI's full path. |
| OpenBot keeps using another CLI | Confirm `OPENBOT_OPENCODE_PATH` in the user environment and fully restart OpenBot. |
| `plugin loaded but no proxy environment matches` | The ACP process started without the wrapper or without WARP. Check `warp-wrapper.log`. |
| `WARP is unavailable; ... retry disabled` | WARP did not answer within ~10 s. Run `warp-cli mode proxy` and `warp-cli connect`. |
| `warp-cli connect` fails | WARP is not signed in/registered. Open the WARP client and connect once. |
| Proxy connected, but `curl -x` fails | WARP is not in proxy mode, or the port is not 40000. Adjust `WARP_PROXY_URL`. |
| `curl.exe not found` | Old Windows without curl. Update Windows or start OpenCode with the proxy variables manually. |
| OpenBot and Desktop sessions mixed | Set `OPENBOT_OC_HOME` to a separate folder and restart OpenBot. |
| Turn fails with `ECONNREFUSED` | The proxy was set but WARP dropped mid-turn. The plugin does not handle `provider.transport`; reconnect WARP and retry. |
| Still limited after rotations | Likely an account-level quota, not an IP one. Rotating the IP will not help. |

## Linux/macOS

OpenBot also runs outside Windows. The principle is the same: a script named `opencode` that isolates `XDG_DATA_HOME`/`XDG_STATE_HOME`, exports the proxy, and executes the real CLI. Example for Linux/macOS (adjust the CLI path):

```sh
#!/bin/sh
set -eu

OC_HOME="${OPENBOT_OC_HOME:-$HOME/.local/share/openbot/opencode-cli}"
OC_CLI="${OPENBOT_OC_CLI:-opencode}"
PROXY="${WARP_PROXY_URL:-http://127.0.0.1:40000}"

mkdir -p "$OC_HOME/data" "$OC_HOME/state"
export XDG_DATA_HOME="$OC_HOME/data"
export XDG_STATE_HOME="$OC_HOME/state"

if [ "${1:-}" != "--version" ]; then
  if curl -fsS -m 3 -x "$PROXY" https://www.cloudflare.com/cdn-cgi/trace | grep -q 'warp=on'; then
    export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" ALL_PROXY="$PROXY"
    export NO_PROXY="localhost,127.0.0.1,::1"
  fi
fi

exec "$OC_CLI" "$@"
```

Save it as `~/bin/opencode`, run `chmod +x`, and point `OPENBOT_OPENCODE_PATH` at it. On Linux/macOS you can export the path from `~/.profile`/`~/.zshrc`; restart OpenBot afterwards.

## Limits

- Applies to OpenBot when the provider is **OpenCode**. Codex, Claude, plain Grok, and custom ACP agents do not go through this wrapper.
- OpenCode caps a request at roughly **10 physical attempts**; the plugin rotates within that cap.
- Rotating WARP briefly interrupts every WARP user on the machine.
- The wrapper does not change the system proxy: the variables apply only to the OpenCode process.
- The plugin cannot fix an account-level quota. If the limit belongs to the account rather than the IP, rotating the IP does not help.

## Files

```text
openbot/opencode.cmd          Windows wrapper
openbot/README.md             Portuguese guide
openbot/README.en.md          this guide
```

Back to the main README: [README.md](../README.md).
