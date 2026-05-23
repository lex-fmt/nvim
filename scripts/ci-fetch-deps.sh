#!/usr/bin/env bash
# Pre-check hook for the canonical nvim-plugin-ci.yml@v1 thin caller.
#
# Three steps the bespoke test.yml used to do inline:
#   1. Verify the generated theme is in sync with comms (python check)
#   2. Download + install lexd-lsp at the pinned version (from shared/lex-deps.json)
#   3. Download + extract tree-sitter-lex source at the pinned version
#
# Invoked from .github/workflows/test.yml's `pre-check: scripts/ci-fetch-deps.sh`.
#
# The downloads use `gh release download` (the GITHUB_TOKEN-authenticated path)
# instead of the prior `robinraju/release-downloader` GH-action — pre-check
# hooks are bash, not composite actions. `gh release download` is in the
# default ubuntu-latest runner image.

set -euo pipefail

# --- Architecture detection for the lexd-lsp binary -----------------------
# `uname -m` ranges: x86_64 → x86_64, aarch64 → aarch64, arm64 → aarch64.
# Map to the asset filename suffix the release/ rust-cli.yml@v1 produces.
case "$(uname -m)" in
    x86_64)          LSP_ARCH_SUFFIX="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64)   LSP_ARCH_SUFFIX="aarch64-unknown-linux-gnu" ;;
    *)
        echo "::error::Unsupported runner architecture: $(uname -m)" >&2
        exit 2
        ;;
esac

# --- Install destination with non-root fallback ---------------------------
# Prefer /usr/local/bin (matches the bespoke workflow and ubuntu-latest CI).
# Fall back to ~/.local/bin if /usr/local/bin isn't writable AND sudo isn't
# available (e.g. container-based runners, local dev).
if [ -w /usr/local/bin ] || sudo -n true 2>/dev/null; then
    INSTALL_DIR=/usr/local/bin
    INSTALL_CMD=(sudo install -m 0755)
else
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    INSTALL_CMD=(install -m 0755)
    echo "::warning::installing to $INSTALL_DIR (no /usr/local/bin write + no passwordless sudo)"
fi

echo "===== 1. Verify generated theme sync with comms ====="
python3 scripts/gen-theme.py --check

if [ ! -f shared/lex-deps.json ]; then
    echo "::error::shared/lex-deps.json missing — can't pin dep versions" >&2
    exit 2
fi

LSP_VERSION=$(jq -r '.["lexd-lsp"]' shared/lex-deps.json)
LSP_REPO=$(jq -r '.["lexd-lsp-repo"]' shared/lex-deps.json)
TS_VERSION=$(jq -r '.["tree-sitter"]' shared/lex-deps.json)
TS_REPO=$(jq -r '.["tree-sitter-repo"]' shared/lex-deps.json)

# Validate each required key — jq -r prints "null" for missing entries,
# which `gh release download` accepts then fails confusingly downstream.
for var in LSP_VERSION LSP_REPO TS_VERSION TS_REPO; do
    val="${!var}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo "::error::shared/lex-deps.json missing or null entry for $var" >&2
        echo "  current contents:" >&2
        cat shared/lex-deps.json >&2
        exit 2
    fi
done

echo ""
echo "===== 2. Download + install lexd-lsp $LSP_VERSION from $LSP_REPO ($LSP_ARCH_SUFFIX) ====="
mkdir -p /tmp/lexd-lsp-extract
gh release download "$LSP_VERSION" \
    --repo "$LSP_REPO" \
    --pattern "lexd-lsp-${LSP_ARCH_SUFFIX}.tar.gz" \
    --output "/tmp/lexd-lsp-${LSP_ARCH_SUFFIX}.tar.gz" \
    --clobber
tar -xzf "/tmp/lexd-lsp-${LSP_ARCH_SUFFIX}.tar.gz" -C /tmp/lexd-lsp-extract
# arthur-debert/release@v1 packages binaries under <name>-<target>/, but
# earlier releases had the binary at the top level — find it either way.
BIN=$(find /tmp/lexd-lsp-extract -name lexd-lsp -type f | head -1)
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
    echo "::error::lexd-lsp binary not found after tarball extraction" >&2
    echo "  extracted layout:" >&2
    find /tmp/lexd-lsp-extract -maxdepth 3 -type f >&2
    exit 2
fi
"${INSTALL_CMD[@]}" "$BIN" "$INSTALL_DIR/lexd-lsp"
echo "Installed: $INSTALL_DIR/lexd-lsp"

echo ""
echo "===== 3. Download + extract tree-sitter source $TS_VERSION from $TS_REPO ====="
mkdir -p /tmp/tree-sitter-lex
gh release download "$TS_VERSION" \
    --repo "$TS_REPO" \
    --pattern 'tree-sitter.tar.gz' \
    --output /tmp/tree-sitter.tar.gz \
    --clobber
tar -xzf /tmp/tree-sitter.tar.gz -C /tmp/tree-sitter-lex
echo "Extracted: $(ls /tmp/tree-sitter-lex | head -5)"
