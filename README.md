# deepclaude

Run [Claude Code](https://docs.claude.com/en/docs/claude-code) against
[DeepSeek](https://platform.deepseek.com)'s Anthropic-compatible API.

You install once, paste your DeepSeek API key once, and from then on just run
`deepclaude` — it sets all the env vars and launches `claude` for you.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/RafiulM/deepclaude/main/install.sh | bash
```

This drops a single `deepclaude` script into `~/.local/bin`. If that directory
isn't on your `PATH`, the installer prints the line to add.

Requires the `claude` CLI to already be installed
([instructions](https://docs.claude.com/en/docs/claude-code)).

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

## Manage your key

```bash
deepclaude config    # re-enter / change the stored key
deepclaude reset     # delete the stored key
```

The key lives in `~/.config/deepclaude/config` with `600` permissions
(owner read/write only). It is stored in plaintext on your machine — anyone
with access to your user account can read it. Treat it like any other local
credential.

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

```bash
rm ~/.local/bin/deepclaude
rm -rf ~/.config/deepclaude
```
