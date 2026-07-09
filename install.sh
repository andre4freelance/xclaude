#!/usr/bin/env bash
#
# <provider>claude installer — installs a Claude Code wrapper for any
# Anthropic-compatible AI API (DeepSeek, GLM/Z.AI, or a custom endpoint).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/andre4freelance/xclaude/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- glm      # non-interactive: pick the provider up front
#
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/andre4freelance/xclaude/main"
BIN_DIR="${DEEPCLAUDE_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*" >&2; }

PROVIDER="${1:-${AICLAUDE_PROVIDER:-}}"

if [ -z "$PROVIDER" ]; then
  say ""
  say "Which AI provider are you setting up?"
  say "Known presets: deepseek, glm — or type any other name for a custom endpoint."
  printf 'Provider name: ' >&2
  if ! IFS= read -r PROVIDER < /dev/tty 2>/dev/null; then
    IFS= read -r PROVIDER || true
  fi
fi

# Normalize to lowercase letters/digits only — this becomes part of the
# command name and the config directory name.
PROVIDER="$(printf '%s' "$PROVIDER" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"

if [ -z "$PROVIDER" ]; then
  say "Need a provider name (letters/numbers only), e.g. 'deepseek' or 'glm'."
  exit 1
fi

CMD_NAME="${PROVIDER}claude"
mkdir -p "$BIN_DIR"

say "Installing $CMD_NAME to $BIN_DIR ..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REPO_RAW/aiclaude" -o "$BIN_DIR/$CMD_NAME"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$BIN_DIR/$CMD_NAME" "$REPO_RAW/aiclaude"
else
  say "Need curl or wget."
  exit 1
fi
chmod +x "$BIN_DIR/$CMD_NAME"

say "Installed: $BIN_DIR/$CMD_NAME"

case ":$PATH:" in
  *":$BIN_DIR:"*)
    say "Ready. Run: $CMD_NAME"
    ;;
  *)
    say ""
    say "NOTE: $BIN_DIR is not on your PATH."
    say "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
    say "  export PATH=\"$BIN_DIR:\$PATH\""
    say "Then open a new terminal and run: $CMD_NAME"
    ;;
esac

say ""
say "Setting up another provider? Just run this installer again with a"
say "different name — each one gets its own command and its own config."
