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

OWNER="andre4freelance"
REPO="xclaude"
BRANCH="main"
BIN_DIR="${XCLAUDE_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*" >&2; }

# Pick a downloader.
if command -v curl >/dev/null 2>&1; then
  DL=curl
elif command -v wget >/dev/null 2>&1; then
  DL=wget
else
  say "Need curl or wget."
  exit 1
fi

# Download $1 to file $2. $3=1 sends the GitHub API "raw" Accept header.
_get() {
  local url="$1" out="$2" raw="${3:-0}"
  if [ "$DL" = curl ]; then
    if [ "$raw" = 1 ]; then
      curl -fsSL -H "Accept: application/vnd.github.raw" "$url" -o "$out" 2>/dev/null
    else
      curl -fsSL "$url" -o "$out" 2>/dev/null
    fi
  else
    if [ "$raw" = 1 ]; then
      wget -q --header="Accept: application/vnd.github.raw" -O "$out" "$url" 2>/dev/null
    else
      wget -qO "$out" "$url" 2>/dev/null
    fi
  fi
}

# Fetch a repo-relative path to file $2, trying several hosts because
# raw.githubusercontent.com rate-limits (HTTP 429) hard on some networks.
fetch() {
  local path="$1" out="$2"
  _get "https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH/$path" "$out" 0 && [ -s "$out" ] && return 0
  _get "https://api.github.com/repos/$OWNER/$REPO/contents/$path?ref=$BRANCH" "$out" 1 && [ -s "$out" ] && return 0
  _get "https://cdn.jsdelivr.net/gh/$OWNER/$REPO@$BRANCH/$path" "$out" 0 && [ -s "$out" ] && return 0
  return 1
}

PROVIDER="${1:-${XCLAUDE_PROVIDER:-}}"

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
if ! fetch "xclaude" "$BIN_DIR/$CMD_NAME"; then
  say "Download failed from every mirror (raw.githubusercontent.com, GitHub API, jsDelivr)."
  say "Check your connection and try again in a minute."
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
