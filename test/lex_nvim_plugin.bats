#!/usr/bin/env bats

setup() {
    # Get the directory of the test file
    export SCRIPT_DIR="$BATS_TEST_DIRNAME"
    export PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
    export MINIMAL_INIT="$SCRIPT_DIR/minimal_init.lua"
    export NVIM_APPNAME="lex-test"
}

@test "Plugin loads successfully" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_plugin_loads.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "No runtime errors emitted during LSP attach" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_no_errors_on_attach.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Binary manager handles version resolution" {
    run nvim --headless -u NONE -l "$SCRIPT_DIR/test_binary_manager.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Trust prompt formatters and response builder" {
    run nvim --headless -u NONE -l "$SCRIPT_DIR/test_trust_prompt.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Trust prompt LSP wiring with vim.fn.confirm patched" {
    run nvim --headless -u NONE -l "$SCRIPT_DIR/test_lsp_trust_prompt.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Filetype detection for .lex files" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_filetype.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP hover functionality" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_hover.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP go-to-definition functionality" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_definition.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP semantic tokens functionality" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_semantic_tokens.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP document symbols functionality" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_document_symbols.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP folding ranges functionality" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_folding_ranges.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP references functionality" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_references.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP document links functionality" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_document_links.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Tree-sitter parser loads and parses" {
    run nvim --headless -u NONE -l "$SCRIPT_DIR/test_treesitter.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Tree-sitter injection zones detected" {
    run nvim --headless -u NONE -l "$SCRIPT_DIR/test_injections.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Table blocks highlight correctly and skip injection" {
    run nvim --headless -u NONE -l "$SCRIPT_DIR/test_table_highlighting.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Table cell navigation with Tab/Shift-Tab" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_table_navigation.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Reorder footnotes command via LSP" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_reorder_footnotes.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Extract to include command via LSP" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_extract_to_include.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Parser diagnostics surface in the buffer" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_diagnostics.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Label-policy LSP surface (diagnostics + quickfix + hover + completion)" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_label_policy.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "LSP range formatting" {
    run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_range_formatting.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

@test "Format-on-save autocmd opt-in" {
    run nvim --headless -u NONE -l "$SCRIPT_DIR/test_format_on_save.lua"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TEST_PASSED" ]]
}

# Skipped: requires lex CLI which is not available in CI
# @test "LSP formatting functionality" {
#     run nvim --headless -u "$MINIMAL_INIT" -l "$SCRIPT_DIR/test_lsp_formatting.lua"
#     [ "$status" -eq 0 ]
#     [[ "$output" =~ "TEST_PASSED" ]]
# }
