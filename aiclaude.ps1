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

$Repo = 'https://raw.githubusercontent.com/andre4freelance/xclaude/main'

function Get-ProviderDefaults([string]$Name) {
  switch ($Name) {
    'deepseek' { return @{ Url = 'https://api.deepseek.com/anthropic'; Main = 'deepseek-v4-pro[1m]'; Haiku = 'deepseek-v4-flash' } }
    'glm'      { return @{ Url = 'https://api.z.ai/api/anthropic'; Main = 'glm-4.7'; Haiku = 'glm-4.5-air' } }
    default    { return $null }
  }
}

function Save-Config([string]$Key, [string]$Url, [string]$Main, [string]$Haiku) {
  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
  $lines = @("KEY=$Key", "BASE_URL=$Url", "MODEL_MAIN=$Main", "MODEL_HAIKU=$Haiku")
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
  Write-Host ''
}

function Print-Help {
  Write-Host "Usage: $Self [command] [args] | [claude arguments]"
  Write-Host ''
  Write-Host "  $Self                          run claude with this provider's config"
  Write-Host "  $Self config [KEY]             full setup, or just replace the key"
  Write-Host "  $Self set-url [URL]            change the base URL"
  Write-Host "  $Self set-model [MAIN] [HAIKU] change the model name(s)"
  Write-Host "  $Self reset                    delete the stored config"
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
      Write-Host 'Done.'
      exit 0
    }
    '^(reset|--reset)$' {
      if (Test-Path $ConfigFile) { Remove-Item $ConfigFile -Force }
      Write-Host 'Stored config removed.'
      exit 0
    }
    '^(update|--update|upgrade|--upgrade)$' {
      Write-Host "Updating $Self to the latest version..."
      $target = $MyInvocation.MyCommand.Path
      $tmp = "$target.new"
      Invoke-WebRequest -UseBasicParsing "$Repo/aiclaude.ps1" -OutFile $tmp
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

$env:ANTHROPIC_BASE_URL             = $Url
$env:ANTHROPIC_AUTH_TOKEN           = $Key
$env:ANTHROPIC_MODEL                = $Main
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $Main
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Main
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $Haiku
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $Haiku
$env:CLAUDE_CODE_EFFORT_LEVEL       = 'max'

& claude --dangerously-skip-permissions @args
exit $LASTEXITCODE
