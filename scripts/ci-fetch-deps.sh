#!/usr/bin/env bash
# Pre-check hook for nvim-plugin-ci.yml@v1.
#
# 1. Verify the generated theme is in sync with comms
# 2. Download deps to resources/ via the canonical fetch-deps tool
# 3. Bridge repo-relative resources/ to the absolute paths CI expects
#    (/usr/local/bin/lexd-lsp, /tmp/tree-sitter-lex)
#
# Invoked from .github/workflows/test.yml's `pre-check: scripts/ci-fetch-deps.sh`.

set -euo pipefail

# ---- 1. Verify generated theme sync with comms -----------------------------

echo "===== 1. Verify generated theme sync with comms ====="
python3 app-bin/gen-theme.py --check

# ---- 2. Fetch deps via canonical tool --------------------------------------

echo ""
echo "===== 2. Fetch dependencies via fetch-deps ====="

# fetch-deps lives in arthur-debert/release bin/ (on PATH locally via dodot).
# CI runners don't have it; download from release@main when absent.
if ! command -v fetch-deps &>/dev/null; then
    FETCH_DEPS_URL="https://raw.githubusercontent.com/arthur-debert/release/main/bin/fetch-deps"
    FETCH_DEPS_BIN="$(mktemp)"
    trap 'rm -f "$FETCH_DEPS_BIN"' EXIT
    curl -fsSL "$FETCH_DEPS_URL" -o "$FETCH_DEPS_BIN"
    chmod +x "$FETCH_DEPS_BIN"
    FETCH_DEPS="$FETCH_DEPS_BIN"
else
    FETCH_DEPS="fetch-deps"
fi

"$FETCH_DEPS"

# ---- 3. Bridge to absolute paths CI expects --------------------------------

echo ""
echo "===== 3. Install to system paths ====="

# lexd-lsp binary: install to /usr/local/bin (or ~/.local/bin fallback)
if [ -w /usr/local/bin ] || sudo -n true 2>/dev/null; then
    INSTALL_DIR=/usr/local/bin
    INSTALL_CMD=(sudo install -m 0755)
else
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    INSTALL_CMD=(install -m 0755)
    echo "::warning::installing to $INSTALL_DIR (no /usr/local/bin write + no passwordless sudo)"
fi

"${INSTALL_CMD[@]}" resources/lexd-lsp "$INSTALL_DIR/lexd-lsp"
echo "Installed: $INSTALL_DIR/lexd-lsp"

# tree-sitter: tests compile from C source (src/parser.c) and expect the
# full tree-sitter-lex checkout at LEX_TREESITTER_PATH=/tmp/tree-sitter-lex
rm -rf /tmp/tree-sitter-lex
cp -r resources/tree-sitter-lex /tmp/tree-sitter-lex
echo "Bridged tree-sitter resources to /tmp/tree-sitter-lex"
ls /tmp/tree-sitter-lex | head -10
