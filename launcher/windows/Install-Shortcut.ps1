[CmdletBinding()]
param(
  [string]$ShortcutPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'OpenCode (WARP).lnk'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$vbs = Join-Path $PSScriptRoot 'OpenCodeWARP.vbs'
if (-not (Test-Path -LiteralPath $vbs)) {
  throw "OpenCodeWARP.vbs was not found next to this script."
}

$app = $env:OPENCODE_APP_PATH
if (-not $app -or -not (Test-Path -LiteralPath $app)) {
  $app = Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe'
}

if (Test-Path -LiteralPath $ShortcutPath) {
  if (-not $Force) {
    $answer = Read-Host "A shortcut already exists at:`n  $ShortcutPath`n`nOverwrite it? [y/N]"
    if ($answer -notmatch '^(y|yes|s|sim)$') {
      Write-Host 'Cancelled. The existing shortcut was not changed.'
      exit 0
    }
  }

  $backup = "$ShortcutPath.bak"
  Copy-Item -LiteralPath $ShortcutPath -Destination $backup -Force
  Write-Host "Backup of the previous shortcut: $backup"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$shortcut.Arguments = '"' + $vbs + '"'

if (Test-Path -LiteralPath $app) {
  $shortcut.WorkingDirectory = [IO.Path]::GetDirectoryName($app)
  $shortcut.IconLocation = "$app,0"
} else {
  $shortcut.WorkingDirectory = $PSScriptRoot
  Write-Warning "OpenCode.exe was not found at $app. The shortcut will still be created, but the launcher will show an error until OpenCode is installed or OPENCODE_APP_PATH is set."
}

$shortcut.Description = 'Open OpenCode with the Cloudflare WARP proxy'
$shortcut.Save()

Write-Host "Shortcut created: $ShortcutPath"
Write-Host "WARP proxy: http://127.0.0.1:40000"
