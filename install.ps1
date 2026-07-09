# <provider>claude installer for Windows (PowerShell).
# Usage:
#   irm https://raw.githubusercontent.com/andre4freelance/xclaude/main/install.ps1 | iex
#   $env:AICLAUDE_PROVIDER='glm'; irm .../install.ps1 | iex   # non-interactive

$ErrorActionPreference = 'Stop'

$Repo = 'https://raw.githubusercontent.com/andre4freelance/xclaude/main'

$Provider = $env:AICLAUDE_PROVIDER
if (-not $Provider) {
  Write-Host ''
  Write-Host 'Which AI provider are you setting up?'
  Write-Host 'Known presets: deepseek, glm - or type any other name for a custom endpoint.'
  $Provider = Read-Host 'Provider name'
}
$Provider = ($Provider.ToLower() -replace '[^a-z0-9]', '')

if (-not $Provider) {
  Write-Host "Need a provider name (letters/numbers only), e.g. 'deepseek' or 'glm'."
  exit 1
}

$CmdName = "${Provider}claude"
$Dest = Join-Path $env:LOCALAPPDATA "Programs\$CmdName"

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

Write-Host "Installing $CmdName to $Dest ..."
Invoke-WebRequest -UseBasicParsing "$Repo/aiclaude.ps1" -OutFile (Join-Path $Dest "$CmdName.ps1")

# A .cmd shim so the command works from cmd.exe and PowerShell alike.
$shim = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$CmdName.ps1" %*
"@
Set-Content -Path (Join-Path $Dest "$CmdName.cmd") -Value $shim -Encoding ASCII

# Put the install dir on the user PATH if it isn't already.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
if ($userPath -notlike "*$Dest*") {
  $newPath = if ($userPath) { "$userPath;$Dest" } else { $Dest }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  $env:Path = "$env:Path;$Dest"
  Write-Host "Added $Dest to your user PATH."
  Write-Host 'Open a NEW terminal for it to take effect.'
}

Write-Host "Installed. Run: $CmdName"
Write-Host ''
Write-Host 'Setting up another provider? Run this installer again with a'
Write-Host 'different name - each one gets its own command and its own config.'
