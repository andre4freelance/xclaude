# xclaude

Run [Claude Code](https://docs.claude.com/en/docs/claude-code) against **any**
Anthropic-compatible AI API — DeepSeek, GLM (Z.AI), or a custom/unofficial
endpoint of your own.

Install once per provider, enter that provider's API key once, and from then
on just run the command it gave you — it sets all the env vars and launches
`claude` for you.

> Requires the `claude` CLI to already be installed
> ([instructions](https://docs.claude.com/en/docs/claude-code)).

## How naming works

The installer asks which provider you're setting up and names the command
`<provider>claude`:

| You type    | Command you get |
| ----------- | ---------------- |
| `deepseek`  | `deepseekclaude`  |
| `glm`       | `glmclaude`       |
| `mycompany` | `mycompanyclaude` |

You can install as many providers as you like, side by side — each gets its
own command and its own stored config, so `deepseekclaude` and `glmclaude`
never interfere with each other.

## Install (one command)

### macOS / Linux

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/andre4freelance/xclaude@main/install.sh | bash
```

Asks which provider you're setting up, then installs `<provider>claude` into
`~/.local/bin`. If that directory isn't on your `PATH`, the installer prints
the line to add. To skip the prompt (e.g. in scripts):

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/andre4freelance/xclaude@main/install.sh | bash -s -- glm
```

> **Why jsDelivr and not `raw.githubusercontent.com`?** GitHub's raw host
> rate-limits (HTTP 429) aggressively on some networks. jsDelivr is a CDN
> that doesn't, so it's the reliable default. The `raw...` URL still works
> when you aren't limited — and once installed, the wrapper's own downloads
> (like `update`) automatically fall back across raw → GitHub API → jsDelivr,
> so you never depend on a single host.

### Windows (PowerShell)

```powershell
irm https://cdn.jsdelivr.net/gh/andre4freelance/xclaude@main/install.ps1 | iex
```

Installs `<provider>claude` into `%LOCALAPPDATA%\Programs\<provider>claude`
and adds it to your user `PATH`. Open a **new** terminal afterward.

> On Windows you can also use the macOS/Linux command above from **Git Bash**
> or **WSL**.

Run the installer again for each additional provider you want.

## Use

First run asks for the base URL, the model name(s), and the API key, then
saves them:

```bash
glmclaude
```

Every run after that just works — same config, no prompts. Any arguments
pass straight through to `claude`:

```bash
glmclaude "refactor this module"
glmclaude --help
```

### Known presets vs. custom / unofficial sources

If the provider name is a known preset (`deepseek`, `glm`), the base URL and
model names are pre-filled — press Enter to accept them, or type your own to
override (e.g. a self-hosted mirror, a reseller, or any endpoint that isn't
the provider's official one). Unknown provider names just start with empty
fields, so nothing is assumed for you.

### Ways to provide the key

The key is resolved in this order:

1. `<name>claude config <KEY>` — set it inline, no prompt.
2. The stored config file — set on a previous run.
3. `<PROVIDER>_API_KEY` environment variable (e.g. `GLM_API_KEY`,
   `DEEPSEEK_API_KEY`) — used and saved for next time.
4. Interactive prompt — asked for automatically if none of the above is set.

## Manage config

```bash
<name>claude config              # redo full setup (URL + models + key), interactive
<name>claude config <KEY>        # change just the stored key, no prompt
<name>claude set-url <URL>       # change just the base URL
<name>claude set-model <MAIN> [HAIKU]   # change the model name(s)
<name>claude set-effort <LEVEL>  # pin effort, or 'off' to control it in-session
<name>claude set-context <MODE>  # context window: 1m | default | auto
<name>claude reset               # delete everything stored for this provider
```

`change-key`/`change`/`set-key` are accepted as aliases for `config`;
`change-url`/`url` for `set-url`; `change-model`/`model` for `set-model`;
`change-effort`/`effort` for `set-effort`; `change-context`/`context` for
`set-context`.

### Context window (1M vs 200K)

Claude Code assumes a **200K-token** context window for any model it doesn't
recognize — which is every third-party model. If your model actually supports
a **1M** window (e.g. GLM-5.2, DeepSeek), tell the wrapper so Claude Code
accounts for the full window and compacts at the right time:

```bash
<name>claude set-context 1m       # use the 1M window
<name>claude set-context default  # standard 200K window
<name>claude set-context auto     # ask the provider and pick automatically
```

`auto` reads the model's advertised `max_input_tokens` from the provider's
OpenAI-style `/v1/models` endpoint (needs `python3`); if it can't tell, it
asks you to choose manually. Under the hood, `1m` appends the `[1m]` suffix
Claude Code uses to select its 1M window — and Claude Code **strips that
suffix before the request reaches your provider**, so the provider still sees
the plain model name.

### Effort level

By default the wrapper does **not** set a fixed effort level, so the `/effort`
command works normally inside the session and persists to your Claude Code
settings. If you'd rather pin it (e.g. always max on a cheap model), run
`<name>claude set-effort max` — valid levels are `low`, `medium`, `high`,
`xhigh`, `max`. Pinning it exports `CLAUDE_CODE_EFFORT_LEVEL`, which **takes
priority over — and disables — in-session `/effort`**; run
`<name>claude set-effort off` to hand control back to `/effort`.

## Update

```bash
<name>claude update    # pull the latest version of this script
```

| Platform        | Where config is stored                                  |
| --------------- | --------------------------------------------------------- |
| macOS / Linux   | `~/.config/<name>claude/config` (perms `600`)              |
| Windows         | `%APPDATA%\<name>claude\config` (ACL: you only)             |

It is stored in plaintext on your machine — anyone with access to your user
account can read it. Treat it like any other local credential.

## What it sets

```sh
ANTHROPIC_BASE_URL="<the configured base URL>"
ANTHROPIC_AUTH_TOKEN="<the configured API key>"
ANTHROPIC_MODEL="<main model>"          # + "[1m]" suffix if context = 1m
ANTHROPIC_DEFAULT_OPUS_MODEL="<main model>"      # + "[1m]" if context = 1m
ANTHROPIC_DEFAULT_SONNET_MODEL="<main model>"    # + "[1m]" if context = 1m
ANTHROPIC_DEFAULT_HAIKU_MODEL="<the configured haiku/cheap model>"
CLAUDE_CODE_SUBAGENT_MODEL="<the configured haiku/cheap model>"
# CLAUDE_CODE_EFFORT_LEVEL is set ONLY if you pinned one via set-effort
```

Then runs: `claude --dangerously-skip-permissions "$@"`

> **Note:** `--dangerously-skip-permissions` lets Claude run tools without
> per-action approval prompts. Convenient, but it means commands and file
> edits execute without asking. Use it in a directory you trust.

## Uninstall

**macOS / Linux**

```bash
rm ~/.local/bin/<name>claude
rm -rf ~/.config/<name>claude
```

**Windows (PowerShell)**

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\<name>claude"
Remove-Item -Recurse -Force "$env:APPDATA\<name>claude"
```

Repeat per installed provider.
