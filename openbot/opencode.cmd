@echo off
rem ============================================================
rem  opencode-warp-retry - OpenCode wrapper for OpenBot (ACP)
rem
rem  OpenBot starts its own `opencode acp` process and expects an
rem  ACP server on stdin/stdout. This wrapper:
rem    1) isolates OpenBot's OpenCode data and state
rem       (XDG_DATA_HOME / XDG_STATE_HOME) from OpenCode Desktop;
rem    2) makes sure the WARP proxy is set for this process, since
rem       the plugin only enables itself when HTTPS_PROXY /
rem       HTTP_PROXY / ALL_PROXY point at the WARP proxy;
rem    3) appends every decision to
rem       <OPENBOT_OC_HOME>\state\warp-wrapper.log.
rem
rem  Nothing is written to stdout: ACP owns stdin/stdout.
rem
rem  Optional configuration (environment variables):
rem    OPENBOT_OC_HOME       base folder for OpenBot's OpenCode
rem                          default: %LOCALAPPDATA%\OpenBot\opencode-cli
rem    OPENBOT_OC_CLI        full path to opencode-cli.exe
rem    WARP_PROXY_URL        WARP proxy URL
rem                          default: http://127.0.0.1:40000
rem    WARP_AUTOCONNECT      set to 0 to skip `warp-cli connect`
rem ============================================================
setlocal EnableExtensions

rem ---------- 1. isolated data/state -------------------------
if not defined OPENBOT_OC_HOME set "OPENBOT_OC_HOME=%LOCALAPPDATA%\OpenBot\opencode-cli"
if "%OPENBOT_OC_HOME:~-1%"=="\" set "OPENBOT_OC_HOME=%OPENBOT_OC_HOME:~0,-1%"

set "OPENBOT_OC_DATA=%OPENBOT_OC_HOME%\data"
set "OPENBOT_OC_STATE=%OPENBOT_OC_HOME%\state"

if not exist "%OPENBOT_OC_DATA%"  mkdir "%OPENBOT_OC_DATA%"  2>nul
if not exist "%OPENBOT_OC_STATE%" mkdir "%OPENBOT_OC_STATE%" 2>nul
if not exist "%OPENBOT_OC_DATA%" (
  echo [warp-retry] could not create "%OPENBOT_OC_DATA%" 1>&2
  exit /b 1
)
if not exist "%OPENBOT_OC_STATE%" (
  echo [warp-retry] could not create "%OPENBOT_OC_STATE%" 1>&2
  exit /b 1
)

set "XDG_DATA_HOME=%OPENBOT_OC_DATA%"
set "XDG_STATE_HOME=%OPENBOT_OC_STATE%"
set "WARP_LOG=%OPENBOT_OC_STATE%\warp-wrapper.log"

rem ---------- 2. locate the real OpenCode CLI ----------------
set "OC_CLI=%OPENBOT_OC_CLI%"
if defined OC_CLI if not exist "%OC_CLI%" (
  call :log "OPENBOT_OC_CLI is not a file"
  echo [warp-retry] OPENBOT_OC_CLI does not exist: "%OC_CLI%" 1>&2
  exit /b 1
)

if not defined OC_CLI if exist "%LOCALAPPDATA%\Programs\ai.opencode.desktop\resources\opencode-cli.exe" (
  set "OC_CLI=%LOCALAPPDATA%\Programs\ai.opencode.desktop\resources\opencode-cli.exe"
)

if not defined OC_CLI for /f "delims=" %%D in ('dir /b /ad /o-d "%APPDATA%\ai.opencode.desktop\cli" 2^>nul') do (
  if not defined OC_CLI if exist "%APPDATA%\ai.opencode.desktop\cli\%%D\opencode-cli.exe" (
    set "OC_CLI=%APPDATA%\ai.opencode.desktop\cli\%%D\opencode-cli.exe"
  )
)

if not defined OC_CLI (
  call :log "opencode-cli.exe not found"
  echo [warp-retry] opencode-cli.exe not found. Set OPENBOT_OC_CLI to its full path. 1>&2
  exit /b 1
)

>>"%WARP_LOG%" echo %DATE% %TIME% [cli="%OC_CLI%"] 2>nul

rem ---------- 3. no proxy needed just to print a version ----
rem OpenBot runs `<cli> --version` while resolving the provider and
rem gives it 10 s. Probing WARP first could eat that budget, so the
rem version path starts the CLI immediately.
if /i "%~1"=="--version" goto :run
if /i "%~1"=="-v" goto :run
if /i "%~1"=="version" goto :run

rem ---------- 4. WARP proxy --------------------------------
if not defined WARP_PROXY_URL set "WARP_PROXY_URL=http://127.0.0.1:40000"
set "WARP_PROXY=%WARP_PROXY_URL%"
set "WARP_PROBE=%TEMP%\openbot-warp-probe-%RANDOM%%RANDOM%.txt"

set "WARP_CLI="
if exist "%ProgramFiles%\Cloudflare\Cloudflare WARP\warp-cli.exe" set "WARP_CLI=%ProgramFiles%\Cloudflare\Cloudflare WARP\warp-cli.exe"
if not defined WARP_CLI if defined ProgramW6432 if exist "%ProgramW6432%\Cloudflare\Cloudflare WARP\warp-cli.exe" set "WARP_CLI=%ProgramW6432%\Cloudflare\Cloudflare WARP\warp-cli.exe"
if not defined WARP_CLI for /f "delims=" %%W in ('where warp-cli 2^>nul') do if not defined WARP_CLI set "WARP_CLI=%%W"

where curl.exe >nul 2>&1
if errorlevel 1 (
  call :log "curl.exe not found; starting without proxy"
  goto :run
)

call :probe

if not defined WARP_OK (
  if /i not "%WARP_AUTOCONNECT%"=="0" (
    if defined WARP_CLI if exist "%WARP_CLI%" (
      call :log "proxy is down; running warp-cli connect"
      "%WARP_CLI%" connect >nul 2>&1
      for /l %%I in (1,1,3) do (
        if not defined WARP_OK (
          >nul 2>&1 ping -n 2 127.0.0.1
          call :probe
        )
      )
    )
  )
)

if defined WARP_OK (
  set "HTTP_PROXY=%WARP_PROXY%"
  set "HTTPS_PROXY=%WARP_PROXY%"
  set "ALL_PROXY=%WARP_PROXY%"
  set "NO_PROXY=localhost,127.0.0.1,::1"
  call :log "proxy WARP is up (%WARP_PROXY%)"
) else (
  call :log "WARP is unavailable; starting without proxy (retry disabled)"
)

rem ---------- 5. hand over to OpenCode ----------------------
:run
"%OC_CLI%" %*
exit /b %ERRORLEVEL%

:probe
set "WARP_OK="
if exist "%WARP_PROBE%" del "%WARP_PROBE%" >nul 2>&1
curl.exe -s -m 2 -x "%WARP_PROXY%" "https://www.cloudflare.com/cdn-cgi/trace" -o "%WARP_PROBE%" >nul 2>&1
if exist "%WARP_PROBE%" (
  findstr /i /c:"warp=on" "%WARP_PROBE%" >nul 2>&1 && set "WARP_OK=1"
  del "%WARP_PROBE%" >nul 2>&1
)
exit /b 0

:log
>>"%WARP_LOG%" echo %DATE% %TIME% [%~1] 2>nul
exit /b 0
