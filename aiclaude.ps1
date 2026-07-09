# <provider>claude — run Claude Code against any Anthropic-compatible AI API (Windows).
#
# Provider-agnostic: derives which provider to use from its own installed
# filename. Installed as deepseekclaude.ps1 -> DeepSeek; glmclaude.ps1 -> GLM;
# foobarclaude.ps1 -> whatever custom endpoint you configure for it.
#
# Key resolution order:
#   1. `<name>claude config [KEY]`  — set/replace the stored key (inline or prompt)
#   2. stored config file           — set on a previous run
#   3. $env:<PROVIDER>_API_KEY      — used and saved for next time
#   4. interactive prompt           — asks for key (and URL/model on first run)

$ErrorActionPreference = 'Stop'

$Self = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ($Self.Length -le 6 -or $Self.Substring($Self.Length - 6) -ne 'claude') {
  Write-Host "This script must be installed/run as '<provider>claude' (e.g. deepseekclaude, glmclaude)."
  exit 1
}
$Provider = $Self.Substring(0, $Self.Length - 6)
$ProviderUpper = ($Provider.ToUpper() -replace '[^A-Z0-9]', '_')

$ConfigDir  = Join-Path $env:APPDATA $Self
$ConfigFile = Join-Path $ConfigDir 'config'

$Owner = 'andre4freelance'
$RepoName = 'xclaude'
$Branch = 'main'

# Download a repo-relative path to $OutFile, trying several hosts because
# raw.githubusercontent.com rate-limits (HTTP 429) hard on some networks.
function Get-RepoFile([string]$Path, [string]$OutFile) {
  $sources = @(
    @{ Url = "https://raw.githubusercontent.com/$Owner/$RepoName/$Branch/$Path"; Headers = @{} },
    @{ Url = "https://api.github.com/repos/$Owner/$RepoName/contents/$Path`?ref=$Branch"; Headers = @{ Accept = 'application/vnd.github.raw' } },
    @{ Url = "https://cdn.jsdelivr.net/gh/$Owner/$RepoName@$Branch/$Path"; Headers = @{} }
  )
  foreach ($s in $sources) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $s.Url -Headers $s.Headers -OutFile $OutFile
      if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) { return $true }
    } catch { }
  }
  return $false
}

function Get-ProviderDefaults([string]$Name) {
  switch ($Name) {
    'deepseek' { return @{ Url = 'https://api.deepseek.com/anthropic'; Main = 'deepseek-v4-pro[1m]'; Haiku = 'deepseek-v4-flash' } }
    'glm'      { return @{ Url = 'https://api.z.ai/api/anthropic'; Main = 'glm-4.7'; Haiku = 'glm-4.5-air' } }
    default    { return $null }
  }
}

# Best-effort: ask the provider's OpenAI-style /v1/models what the model's max
# input window is. Returns the integer, or 0 if it can't be determined.
function Get-MaxInput([string]$Base, [string]$Key, [string]$Model) {
  $want = $Model
  if ($want.EndsWith('[1m]')) { $want = $want.Substring(0, $want.Length - 4) }
  try {
    $url = ($Base.TrimEnd('/')) + '/v1/models'
    $resp = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $Key" } -TimeoutSec 15
    $data = if ($resp.data) { $resp.data } else { $resp }
    foreach ($m in $data) {
      if ($m.id -eq $want) {
        foreach ($f in @('max_input_tokens','context_length','context_window')) {
          if ($m.PSObject.Properties.Name -contains $f -and $m.$f) { return [int]$m.$f }
        }
      }
    }
  } catch { }
  return 0
}

# Best-effort: detect the current model's window from the provider and store
# CONTEXT accordingly. Silent no-op if it can't be determined.
function Set-AutoContext {
  $base = Get-Field 'BASE_URL'; $key = Get-Field 'KEY'; $model = Get-Field 'MODEL_MAIN'
  if (-not $base -or -not $key -or -not $model) { return }
  $maxTok = Get-MaxInput $base $key $model
  if ($maxTok -le 0) { return }
  if ($maxTok -ge 1000000) {
    Save-Config $key $base $model (Get-Field 'MODEL_HAIKU') (Get-Field 'EFFORT') '1m'
    Write-Host "Context: provider reports $maxTok tokens -> enabled the 1M window."
  } else {
    Save-Config $key $base $model (Get-Field 'MODEL_HAIKU') (Get-Field 'EFFORT') 'default'
    Write-Host "Context: provider reports $maxTok tokens -> using the standard 200K window."
  }
}

function Save-Config([string]$Key, [string]$Url, [string]$Main, [string]$Haiku, [string]$Effort = $null, [string]$Context = $null, [string]$Perms = $null) {
  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
  # $null means "preserve whatever is stored"; '' means clear it.
  if ($null -eq $Effort) { $Effort = Get-Field 'EFFORT' }
  if ($null -eq $Context) { $Context = Get-Field 'CONTEXT' }
  if ($null -eq $Perms) { $Perms = Get-Field 'PERMISSIONS' }
  $lines = @("KEY=$Key", "BASE_URL=$Url", "MODEL_MAIN=$Main", "MODEL_HAIKU=$Haiku", "EFFORT=$Effort", "CONTEXT=$Context", "PERMISSIONS=$Perms")
  Set-Content -Path $ConfigFile -Value $lines -Encoding ASCII
  try {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      "$env:USERDOMAIN\$env:USERNAME", 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $ConfigFile -AclObject $acl
  } catch { }
  Write-Host "Config saved to $ConfigFile"
}

function Get-Field([string]$Name) {
  if (-not (Test-Path $ConfigFile)) { return '' }
  foreach ($line in Get-Content $ConfigFile) {
    if ($line -like "$Name=*") { return $line.Substring($Name.Length + 1) }
  }
  return ''
}

function Read-Secret([string]$Prompt) {
  $secure = Read-Host -AsSecureString $Prompt
  $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $value  = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  return $value.Trim()
}

function Read-Visible([string]$Prompt, [string]$Default) {
  if ($Default) { $value = Read-Host "$Prompt [$Default]" } else { $value = Read-Host $Prompt }
  $value = $value.Trim()
  if (-not $value) { return $Default }
  return $value
}

# Like Read-Visible, but re-prompts on an empty result and gives up after 3
# tries instead of looping forever if stdin has nothing left to give.
function Require-Visible([string]$Prompt, [string]$Default, [string]$Label) {
  $tries = 0
  while ($true) {
    $value = Read-Visible $Prompt $Default
    if ($value) { return $value }
    $tries++
    Write-Host "$Label can't be empty."
    if ($tries -ge 3) { Write-Host 'Aborting after 3 empty attempts.'; exit 1 }
  }
}

function Invoke-Setup([string]$PresetKey) {
  $defaults = Get-ProviderDefaults $Provider
  Write-Host ''
  Write-Host '+------------------------------------------+'
  Write-Host "|  $Self - first-time setup"
  Write-Host '+------------------------------------------+'
  Write-Host ''
  if ($defaults) {
    Write-Host "Provider '$Provider' recognized - defaults pre-filled below."
    Write-Host 'Press Enter to accept a default, or type your own (e.g. a'
    Write-Host 'non-official / self-hosted endpoint).'
  } else {
    Write-Host "Provider '$Provider' isn't a known preset - enter its details."
  }
  Write-Host ''

  $url = Require-Visible 'Base URL (Anthropic-compatible)' $defaults.Url 'URL'
  $main = Require-Visible 'Model for Opus/Sonnet requests' $defaults.Main 'Model name'

  $haikuDefault = if ($defaults.Haiku) { $defaults.Haiku } else { $main }
  $haiku = Read-Visible 'Model for Haiku/subagent requests' $haikuDefault
  if (-not $haiku) { $haiku = $main }

  Write-Host ''
  $key = $PresetKey
  if (-not $key) {
    $tries = 0
    while (-not $key) {
      $key = Read-Secret 'API key'
      if ($key) { break }
      $tries++
      Write-Host "Key can't be empty."
      if ($tries -ge 3) { Write-Host 'Aborting after 3 empty attempts.'; exit 1 }
    }
  }

  Save-Config $key $url $main $haiku
  # By default, take the context window from the provider (best-effort).
  Set-AutoContext
  Write-Host ''
}

function Print-Help {
  Write-Host "Usage: $Self [command] [args] | [claude arguments]"
  Write-Host ''
  Write-Host "  $Self                          run claude with this provider's config"
  Write-Host "  $Self config [KEY]             full setup, or just replace the key"
  Write-Host "  $Self set-url [URL]            change the base URL"
  Write-Host "  $Self set-model [MAIN] [HAIKU] change the model name(s)"
  Write-Host "  $Self set-effort [LEVEL]       pin effort (low|medium|high|xhigh|max),"
  Write-Host "                                 or 'off' to let /effort control it"
  Write-Host "  $Self set-context [MODE]       context window: 1m | default | auto"
  Write-Host "  $Self set-permissions [MODE]   ask (prompt before tools) | skip (no prompts)"
  Write-Host "  $Self reset                    delete the stored config"
  Write-Host "  $Self uninstall                remove the config AND this command"
  Write-Host "  $Self update                   self-update to the latest version"
}

# --- subcommands -------------------------------------------------------------
if ($args.Count -ge 1) {
  switch -Regex ($args[0]) {
    '^(help|--help|-h)$' {
      Print-Help
      exit 0
    }
    '^(config|--config|set-key|--set-key|change|--change|change-key|--change-key)$' {
      if ($args.Count -ge 2) {
        if (Test-Path $ConfigFile) {
          Save-Config $args[1] (Get-Field 'BASE_URL') (Get-Field 'MODEL_MAIN') (Get-Field 'MODEL_HAIKU')
        } else {
          $defaults = Get-ProviderDefaults $Provider
          if ($defaults) {
            Save-Config $args[1] $defaults.Url $defaults.Main $defaults.Haiku
          } else {
            Invoke-Setup $args[1]
          }
        }
      } else {
        Invoke-Setup ''
      }
      Write-Host "Done. Run '$Self' to start."
      exit 0
    }
    '^(set-url|--set-url|change-url|--change-url|url|--url)$' {
      if (-not (Test-Path $ConfigFile)) {
        Write-Host "No config yet - run '$Self config' first."
        exit 1
      }
      if ($args.Count -ge 2) { $newUrl = $args[1] } else { $newUrl = Read-Visible 'Base URL (Anthropic-compatible)' (Get-Field 'BASE_URL') }
      if (-not $newUrl) { Write-Host "URL can't be empty."; exit 1 }
      Save-Config (Get-Field 'KEY') $newUrl (Get-Field 'MODEL_MAIN') (Get-Field 'MODEL_HAIKU')
      Write-Host 'Done.'
      exit 0
    }
    '^(set-model|--set-model|change-model|--change-model|model|--model)$' {
      if (-not (Test-Path $ConfigFile)) {
        Write-Host "No config yet - run '$Self config' first."
        exit 1
      }
      if ($args.Count -ge 2) {
        $newMain = $args[1]
        $newHaiku = if ($args.Count -ge 3) { $args[2] } else { $newMain }
      } else {
        $newMain = Read-Visible 'Model for Opus/Sonnet requests' (Get-Field 'MODEL_MAIN')
        $newHaiku = Read-Visible 'Model for Haiku/subagent requests' (Get-Field 'MODEL_HAIKU')
      }
      if (-not $newMain) { Write-Host "Model can't be empty."; exit 1 }
      if (-not $newHaiku) { $newHaiku = $newMain }
      Save-Config (Get-Field 'KEY') (Get-Field 'BASE_URL') $newMain $newHaiku
      # Re-detect the context window for the new model (best-effort).
      Set-AutoContext
      Write-Host 'Done.'
      exit 0
    }
    '^(set-effort|--set-effort|change-effort|--change-effort|effort|--effort)$' {
      if (-not (Test-Path $ConfigFile)) {
        Write-Host "No config yet - run '$Self config' first."
        exit 1
      }
      $newEffort = if ($args.Count -ge 2) { "$($args[1])".Trim().ToLower() } else { 'off' }
      if (-not $newEffort) { $newEffort = 'off' }
      if ($newEffort -notin @('low','medium','high','xhigh','max','off')) {
        Write-Host "Effort must be: low, medium, high, xhigh, max, or off (off = /effort controls it)."
        exit 1
      }
      Save-Config (Get-Field 'KEY') (Get-Field 'BASE_URL') (Get-Field 'MODEL_MAIN') (Get-Field 'MODEL_HAIKU') $newEffort
      if ($newEffort -eq 'off') {
        Write-Host 'Done. Effort now controlled by /effort inside the session.'
      } else {
        Write-Host "Done. Effort pinned to '$newEffort'."
      }
      exit 0
    }
    '^(set-context|--set-context|change-context|--change-context|context|--context)$' {
      if (-not (Test-Path $ConfigFile)) {
        Write-Host "No config yet - run '$Self config' first."
        exit 1
      }
      $want = if ($args.Count -ge 2) { "$($args[1])".Trim().ToLower() } else { '' }
      $newContext = $null
      switch ($want) {
        { $_ -in @('1m','1000k','1000000') } { $newContext = '1m' }
        { $_ -in @('default','200k','off','') } { $newContext = 'default' }
        'auto' {
          Write-Host "Detecting context window for '$(Get-Field 'MODEL_MAIN')' from $(Get-Field 'BASE_URL') ..."
          $maxTok = Get-MaxInput (Get-Field 'BASE_URL') (Get-Field 'KEY') (Get-Field 'MODEL_MAIN')
          if ($maxTok -le 0) {
            Write-Host "Couldn't auto-detect it. Set it manually instead:"
            Write-Host "  $Self set-context 1m       # 1M-token window"
            Write-Host "  $Self set-context default  # standard 200K window"
            exit 1
          }
          if ($maxTok -ge 1000000) {
            $newContext = '1m'; Write-Host "Detected $maxTok tokens -> enabling the 1M window."
          } else {
            $newContext = 'default'; Write-Host "Detected $maxTok tokens -> keeping the standard 200K window."
          }
        }
        default { Write-Host 'Context must be: 1m, default, or auto.'; exit 1 }
      }
      Save-Config (Get-Field 'KEY') (Get-Field 'BASE_URL') (Get-Field 'MODEL_MAIN') (Get-Field 'MODEL_HAIKU') (Get-Field 'EFFORT') $newContext
      if ($newContext -eq '1m') {
        Write-Host 'Done. 1M context on (appends the [1m] suffix Claude Code needs; stripped before it reaches your provider).'
      } else {
        Write-Host 'Done. Standard 200K context (no [1m] suffix).'
      }
      exit 0
    }
    '^(set-permissions|--set-permissions|permissions|--permissions|perms|--perms)$' {
      if (-not (Test-Path $ConfigFile)) {
        Write-Host "No config yet - run '$Self config' first."
        exit 1
      }
      $want = if ($args.Count -ge 2) { "$($args[1])".Trim().ToLower() } else { '' }
      $newPerms = $null
      switch ($want) {
        { $_ -in @('ask','prompt','safe','on','') } { $newPerms = 'ask' }
        { $_ -in @('skip','yolo','bypass','off') } { $newPerms = 'skip' }
        default { Write-Host 'Permissions must be: ask (prompt before actions) or skip (no prompts).'; exit 1 }
      }
      Save-Config (Get-Field 'KEY') (Get-Field 'BASE_URL') (Get-Field 'MODEL_MAIN') (Get-Field 'MODEL_HAIKU') (Get-Field 'EFFORT') (Get-Field 'CONTEXT') $newPerms
      if ($newPerms -eq 'ask') {
        Write-Host 'Done. Claude will ask before running tools (no --dangerously-skip-permissions).'
      } else {
        Write-Host 'Done. Claude runs tools without asking (--dangerously-skip-permissions).'
      }
      exit 0
    }
    '^(reset|--reset)$' {
      if (Test-Path $ConfigFile) { Remove-Item $ConfigFile -Force }
      Write-Host 'Stored config removed.'
      exit 0
    }
    '^(uninstall|--uninstall|remove|--remove)$' {
      Write-Host "Removing $Self (its config and the command itself)..."
      if (Test-Path $ConfigDir) { Remove-Item $ConfigDir -Recurse -Force }
      $dir = Split-Path -Parent $MyInvocation.MyCommand.Path
      Write-Host "Removed config: $ConfigDir"
      Write-Host "To finish, delete the install folder: $dir"
      Write-Host "  Remove-Item -Recurse -Force `"$dir`""
      exit 0
    }
    '^(update|--update|upgrade|--upgrade)$' {
      Write-Host "Updating $Self to the latest version..."
      $target = $MyInvocation.MyCommand.Path
      $tmp = "$target.new"
      if (-not (Get-RepoFile 'aiclaude.ps1' $tmp)) {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        Write-Host 'Download failed from every mirror. Try again in a minute.'
        exit 1
      }
      Move-Item -Force $tmp $target
      Write-Host "Updated. Run '$Self' to continue."
      exit 0
    }
  }
}

# --- resolve key / URL / models -----------------------------------------------
$Key   = Get-Field 'KEY'
$Url   = Get-Field 'BASE_URL'
$Main  = Get-Field 'MODEL_MAIN'
$Haiku = Get-Field 'MODEL_HAIKU'

if (-not $Key) {
  $envVarName = "${ProviderUpper}_API_KEY"
  $envKey = [Environment]::GetEnvironmentVariable($envVarName)
  if ($envKey) {
    $Key = $envKey.Trim()
    Write-Host "Using `$env:$envVarName from environment."
  }
}

if ((-not $Url) -or (-not $Main)) {
  $defaults = Get-ProviderDefaults $Provider
  if ($defaults) {
    if (-not $Url)   { $Url   = $defaults.Url }
    if (-not $Main)  { $Main  = $defaults.Main }
    if (-not $Haiku) { $Haiku = $defaults.Haiku }
  }
}

if ((-not $Key) -or (-not $Url) -or (-not $Main)) {
  Invoke-Setup $Key
  $Key   = Get-Field 'KEY'
  $Url   = Get-Field 'BASE_URL'
  $Main  = Get-Field 'MODEL_MAIN'
  $Haiku = Get-Field 'MODEL_HAIKU'
}

if (-not $Key) {
  Write-Host "No API key available. Run '$Self config' to set one."
  exit 1
}

# --- launch --------------------------------------------------------------
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host 'claude CLI not found on PATH.'
  Write-Host 'Install Claude Code first: https://docs.claude.com/en/docs/claude-code'
  exit 127
}

# A [1m] suffix on the model name tells Claude Code to use a 1M-token context
# window; it strips the suffix before sending the request to the provider.
$bareMain = if ($Main.EndsWith('[1m]')) { $Main.Substring(0, $Main.Length - 4) } else { $Main }
$mainModel = if ((Get-Field 'CONTEXT') -eq '1m') { "$bareMain[1m]" } else { $bareMain }

$env:ANTHROPIC_BASE_URL             = $Url
$env:ANTHROPIC_AUTH_TOKEN           = $Key
$env:ANTHROPIC_MODEL                = $mainModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $mainModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $mainModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $Haiku
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $Haiku

# Only pin effort if the config asks for it; otherwise leave /effort in charge.
$effort = (Get-Field 'EFFORT').Trim().ToLower()
if ($effort -in @('low','medium','high','xhigh','max')) {
  $env:CLAUDE_CODE_EFFORT_LEVEL = $effort
} else {
  Remove-Item Env:\CLAUDE_CODE_EFFORT_LEVEL -ErrorAction SilentlyContinue
}

# Permissions: default is to let Claude prompt before tools. Only skip those
# prompts when the config explicitly says 'skip'.
if ((Get-Field 'PERMISSIONS') -eq 'skip') {
  & claude --dangerously-skip-permissions @args
} else {
  & claude @args
}
exit $LASTEXITCODE
