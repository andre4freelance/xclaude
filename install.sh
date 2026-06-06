#!/usr/bin/env bash
#
# deepclaude installer.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/RafiulM/deepclaude/main/install.sh | bash
#
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/RafiulM/deepclaude/main"
CMD_NAME="deepclaude"
BIN_DIR="${DEEPCLAUDE_BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$BIN_DIR"

echo "Installing $CMD_NAME to $BIN_DIR ..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REPO_RAW/$CMD_NAME" -o "$BIN_DIR/$CMD_NAME"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$BIN_DIR/$CMD_NAME" "$REPO_RAW/$CMD_NAME"
else
  echo "Need curl or wget." >&2
  exit 1
fi
chmod +x "$BIN_DIR/$CMD_NAME"

echo "Installed: $BIN_DIR/$CMD_NAME"

case ":$PATH:" in
  *":$BIN_DIR:"*)
    echo "Ready. Run: $CMD_NAME"
    ;;
  *)
    echo
    echo "NOTE: $BIN_DIR is not on your PATH."
    echo "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    echo "Then open a new terminal and run: $CMD_NAME"
    ;;
esac
