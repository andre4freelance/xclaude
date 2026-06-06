# deepclaude — run Claude Code against DeepSeek's Anthropic-compatible API (Windows).
#
# Key resolution order:
#   1. `deepclaude config [KEY]`  — set/replace the stored key (inline or prompt)
#   2. stored config file         — set on a previous run
#   3. $env:DEEPSEEK_API_KEY      — used and saved for next time
#   4. interactive prompt         — asks for the key if you haven't included it yet

$ErrorActionPreference = 'Stop'

$ConfigDir  = Join-Path $env:APPDATA 'deepclaude'
$ConfigFile = Join-Path $ConfigDir 'config'

function Save-Key([string]$Key) {
  $Key = $Key.Trim()
  if ([string]::IsNullOrEmpty($Key)) {
    Write-Host 'Refusing to save an empty key.'
    return
  }
  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
  Set-Content -Path $ConfigFile -Value ("DEEPSEEK_API_KEY=" + $Key) -Encoding ASCII
  # Restrict the file to the current user only.
  try {
    $acl  = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      "$env:USERDOMAIN\$env:USERNAME", 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $ConfigFile -AclObject $acl
  } catch { }
  Write-Host "Key saved to $ConfigFile"
}

function Get-Key {
  if (-not (Test-Path $ConfigFile)) { return $null }
  foreach ($line in Get-Content $ConfigFile) {
    if ($line -like 'DEEPSEEK_API_KEY=*') {
      return $line.Substring('DEEPSEEK_API_KEY='.Length)
    }
  }
  return $null
}

function Invoke-Setup {
  Write-Host ''
  Write-Host '+------------------------------------------+'
  Write-Host '|  deepclaude - first-time setup           |'
  Write-Host '+------------------------------------------+'
  Write-Host ''
  Write-Host "Claude Code will run against DeepSeek's API."
  Write-Host 'You only need to enter your key once.'
  Write-Host 'Get a key: https://platform.deepseek.com/api_keys'
  Write-Host ''
  for ($i = 0; $i -lt 3; $i++) {
    $secure = Read-Host -AsSecureString 'DeepSeek API key'
    $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key    = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $key = $key.Trim()
    if ($key) { Save-Key $key; return }
    Write-Host "Key can't be empty."
  }
  Write-Host 'Aborting after 3 empty attempts.'
  exit 1
}

# --- subcommands -----------------------------------------------------------
if ($args.Count -ge 1) {
  switch -Regex ($args[0]) {
    '^(config|--config|set-key|--set-key)$' {
      if ($args.Count -ge 2) { Save-Key $args[1] } else { Invoke-Setup }
      Write-Host "Done. Run 'deepclaude' to start."
      exit 0
    }
    '^(reset|--reset)$' {
      if (Test-Path $ConfigFile) { Remove-Item $ConfigFile -Force }
      Write-Host 'Stored key removed.'
      exit 0
    }
  }
}

# --- resolve the key -------------------------------------------------------
$key = Get-Key

if (-not $key -and $env:DEEPSEEK_API_KEY) {
  $key = $env:DEEPSEEK_API_KEY.Trim()
  Write-Host 'Using DEEPSEEK_API_KEY from environment; saving for next time.'
  Save-Key $key
}

if (-not $key) {
  Invoke-Setup
  $key = Get-Key
}

if (-not $key) {
  Write-Host "No API key available. Run 'deepclaude config' to set one."
  exit 1
}

# --- launch ----------------------------------------------------------------
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host 'claude CLI not found on PATH.'
  Write-Host 'Install Claude Code first: https://docs.claude.com/en/docs/claude-code'
  exit 127
}

$env:ANTHROPIC_BASE_URL            = 'https://api.deepseek.com/anthropic'
$env:ANTHROPIC_AUTH_TOKEN          = $key
$env:ANTHROPIC_MODEL               = 'deepseek-v4-pro[1m]'
$env:ANTHROPIC_DEFAULT_OPUS_MODEL  = 'deepseek-v4-pro[1m]'
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = 'deepseek-v4-pro[1m]'
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = 'deepseek-v4-flash'
$env:CLAUDE_CODE_SUBAGENT_MODEL    = 'deepseek-v4-flash'
$env:CLAUDE_CODE_EFFORT_LEVEL      = 'max'

& claude --dangerously-skip-permissions @args
exit $LASTEXITCODE
