# deepclaude

Run [Claude Code](https://docs.claude.com/en/docs/claude-code) against
[DeepSeek](https://platform.deepseek.com)'s Anthropic-compatible API.

Install once with a single command, enter your DeepSeek API key once (it asks
you interactively if you haven't included it yet), and from then on just run
`deepclaude` — it sets all the env vars and launches `claude` for you.

> Requires the `claude` CLI to already be installed
> ([instructions](https://docs.claude.com/en/docs/claude-code)).

## Install (one command)

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/RafiulM/deepclaude/main/install.sh | bash
```

Installs a single `deepclaude` script into `~/.local/bin`. If that directory
isn't on your `PATH`, the installer prints the line to add.

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/RafiulM/deepclaude/main/install.ps1 | iex
```

Installs `deepclaude` into `%LOCALAPPDATA%\Programs\deepclaude` and adds it to
your user `PATH`. Open a **new** terminal afterward.

> On Windows you can also use the macOS/Linux command above from **Git Bash**
> or **WSL**.

## Use

First run asks for your DeepSeek API key (hidden input) and saves it:

```bash
deepclaude
```

Every run after that just works — same key, no prompt. Any arguments pass
straight through to `claude`:

```bash
deepclaude "refactor this module"
deepclaude --help
```

### Ways to provide the key

The key is resolved in this order:

1. `deepclaude config <KEY>` — set it inline, no prompt.
2. The stored config file — set on a previous run.
3. `DEEPSEEK_API_KEY` environment variable — used and saved for next time.
4. Interactive prompt — asked for automatically if none of the above is set.

## Manage your key

```bash
deepclaude config        # re-enter / change the stored key (interactive)
deepclaude config <KEY>  # set the key without a prompt
deepclaude reset         # delete the stored key
```

| Platform        | Where the key is stored                          |
| --------------- | ------------------------------------------------ |
| macOS / Linux   | `~/.config/deepclaude/config` (perms `600`)      |
| Windows         | `%APPDATA%\deepclaude\config` (ACL: you only)    |

It is stored in plaintext on your machine — anyone with access to your user
account can read it. Treat it like any other local credential.

## What it sets

```sh
ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
ANTHROPIC_AUTH_TOKEN="<your DeepSeek API key>"
ANTHROPIC_MODEL="deepseek-v4-pro[1m]"
ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]"
ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]"
ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
CLAUDE_CODE_EFFORT_LEVEL="max"
```

Then runs: `claude --dangerously-skip-permissions "$@"`

> **Note:** `--dangerously-skip-permissions` lets Claude run tools without
> per-action approval prompts. Convenient, but it means commands and file
> edits execute without asking. Use it in a directory you trust.

## Uninstall

**macOS / Linux**

```bash
rm ~/.local/bin/deepclaude
rm -rf ~/.config/deepclaude
```

**Windows (PowerShell)**

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\deepclaude"
Remove-Item -Recurse -Force "$env:APPDATA\deepclaude"
```
