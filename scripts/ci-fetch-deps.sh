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

echo "===== 1. Verify generated theme sync with comms ====="
python3 scripts/gen-theme.py --check

if [ ! -f shared/lex-deps.json ]; then
    echo "::error::shared/lex-deps.json missing — can't pin dep versions"
    exit 1
fi

LSP_VERSION=$(jq -r '.["lexd-lsp"]' shared/lex-deps.json)
LSP_REPO=$(jq -r '.["lexd-lsp-repo"]' shared/lex-deps.json)
TS_VERSION=$(jq -r '.["tree-sitter"]' shared/lex-deps.json)
TS_REPO=$(jq -r '.["tree-sitter-repo"]' shared/lex-deps.json)

echo ""
echo "===== 2. Download + install lexd-lsp $LSP_VERSION from $LSP_REPO ====="
mkdir -p /tmp/lexd-lsp-extract
gh release download "$LSP_VERSION" \
    --repo "$LSP_REPO" \
    --pattern 'lexd-lsp-x86_64-unknown-linux-gnu.tar.gz' \
    --output /tmp/lexd-lsp-x86_64-unknown-linux-gnu.tar.gz \
    --clobber
tar -xzf /tmp/lexd-lsp-x86_64-unknown-linux-gnu.tar.gz -C /tmp/lexd-lsp-extract
# arthur-debert/release@v1 packages binaries under <name>-<target>/, but
# earlier releases had the binary at the top level — find it either way.
BIN=$(find /tmp/lexd-lsp-extract -name lexd-lsp -type f | head -1)
sudo install -m 0755 "$BIN" /usr/local/bin/lexd-lsp
echo "Installed: $(which lexd-lsp)"

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
