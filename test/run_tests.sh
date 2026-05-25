#!/usr/bin/env bash
set -euo pipefail

# Test runner for lex.nvim — replaces the BATS wrapper.
# Runs each test_*.lua file under nvim --headless, checks for
# TEST_PASSED in output, and emits TAP for CI consumption.
#
# Tests that use -u NONE (isolated unit tests not needing the plugin):
NONE_INIT_TESTS=(
    test_binary_manager.lua
    test_trust_prompt.lua
    test_lsp_trust_prompt.lua
    test_treesitter.lua
    test_injections.lua
    test_table_highlighting.lua
    test_format_on_save.lua
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIMAL_INIT="$SCRIPT_DIR/minimal_init.lua"
export NVIM_APPNAME="lex-test"

is_none_init() {
    local name="$1"
    for t in "${NONE_INIT_TESTS[@]}"; do
        [[ "$t" == "$name" ]] && return 0
    done
    return 1
}

# Collect test files (same set the BATS file ran, in declaration order)
TESTS=(
    test_plugin_loads.lua
    test_no_errors_on_attach.lua
    test_binary_manager.lua
    test_trust_prompt.lua
    test_lsp_trust_prompt.lua
    test_filetype.lua
    test_lsp_hover.lua
    test_lsp_definition.lua
    test_lsp_semantic_tokens.lua
    test_lsp_document_symbols.lua
    test_lsp_folding_ranges.lua
    test_lsp_references.lua
    test_lsp_document_links.lua
    test_treesitter.lua
    test_injections.lua
    test_table_highlighting.lua
    test_table_navigation.lua
    test_lsp_reorder_footnotes.lua
    test_lsp_extract_to_include.lua
    test_lsp_diagnostics.lua
    test_lsp_label_policy.lua
    test_lsp_range_formatting.lua
    test_format_on_save.lua
)

total=${#TESTS[@]}
pass=0
fail=0
failures=()
tmpout=$(mktemp)
trap 'rm -f "$tmpout"' EXIT

echo "TAP version 13"
echo "1..$total"

for i in "${!TESTS[@]}"; do
    test_file="${TESTS[$i]}"
    idx=$((i + 1))

    if is_none_init "$test_file"; then
        nvim_args=(--headless -u NONE -l "$SCRIPT_DIR/$test_file")
    else
        nvim_args=(--headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/$test_file")
    fi

    status=0
    nvim "${nvim_args[@]}" >"$tmpout" 2>&1 || status=$?

    if [[ $status -eq 0 ]] && grep -q "TEST_PASSED" "$tmpout"; then
        echo "ok $idx - $test_file"
        pass=$((pass + 1))
    else
        echo "not ok $idx - $test_file"
        if [[ -s "$tmpout" ]]; then
            sed 's/^/# /' "$tmpout"
        fi
        fail=$((fail + 1))
        failures+=("$test_file")
    fi
done

echo ""
echo "# passed: $pass/$total"
if [[ $fail -gt 0 ]]; then
    echo "# FAILED: ${failures[*]}"
    exit 1
fi
