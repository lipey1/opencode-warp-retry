[CmdletBinding()]
param(
  [string]$ShortcutPath = '',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source = Join-Path $repoRoot 'src\index.ts'
if (-not (Test-Path -LiteralPath $source)) {
  throw "Plugin source was not found at $source. Run this script from a full copy of the repository."
}

if ($env:XDG_CONFIG_HOME) {
  $configRoot = Join-Path $env:XDG_CONFIG_HOME 'opencode'
} else {
  $configRoot = Join-Path $env:USERPROFILE '.config\opencode'
}

$pluginDir = Join-Path $configRoot 'plugins\warp-retry'
$target = Join-Path $pluginDir 'index.ts'

New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null

if (Test-Path -LiteralPath $target) {
  $backup = "$target.bak"
  Copy-Item -LiteralPath $target -Destination $backup -Force
  Write-Host "Backup of the previous plugin: $backup"
}

Copy-Item -LiteralPath $source -Destination $target -Force
$hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

Write-Host "Plugin installed: $target"
Write-Host "SHA-256: $hash"

if (Get-Process -Name 'OpenCode' -ErrorAction SilentlyContinue) {
  Write-Host ''
  Write-Host 'OpenCode is running. Quit it completely and reopen it from the "OpenCode (WARP)" shortcut so the plugin loads with the proxy environment.'
}

Write-Host ''
$shortcutArgs = @{ Force = $Force }
if ($ShortcutPath) { $shortcutArgs['ShortcutPath'] = $ShortcutPath }
& (Join-Path $PSScriptRoot 'Install-Shortcut.ps1') @shortcutArgs

Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Make sure Cloudflare WARP is connected in proxy mode:'
Write-Host '       warp-cli mode proxy'
Write-Host '       warp-cli connect'
Write-Host '  2. Quit OpenCode completely.'
Write-Host '  3. Open it from the "OpenCode (WARP)" shortcut.'
