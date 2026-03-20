-- Test: LSP document symbols for tables include rows and cells
-- Tables must NOT be terminal nodes — the outline should show Row/Cell children.
-- Run with: nvim --headless -u test/minimal_init.lua -l test/test_lsp_table_document_symbols.lua

-- Get paths
local script_path = debug.getinfo(1).source:sub(2)
local plugin_dir = vim.fn.fnamemodify(script_path, ":p:h:h")

-- Set up LSP
local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
if not lspconfig_ok then
  print("TEST_FAILED: lspconfig not available")
  vim.cmd("cquit 1")
end

local configs = require("lspconfig.configs")

-- Find the lex-lsp binary
local project_root = vim.fn.fnamemodify(plugin_dir, ":h:h")
local exe = vim.fn.exepath("lex-lsp"); local lex_lsp_path = vim.env.LEX_LSP_PATH or (exe ~= "" and exe) or (project_root .. "/target/debug/lex-lsp")

if vim.fn.filereadable(lex_lsp_path) ~= 1 then
  print("TEST_FAILED: lex-lsp binary not found at " .. lex_lsp_path)
  print("Please build with: cargo build --bin lex-lsp")
  vim.cmd("cquit 1")
end

-- Register lex LSP config
if not configs.lex_lsp then
  configs.lex_lsp = {
    default_config = {
      cmd = { lex_lsp_path },
      filetypes = { "lex" },
      root_dir = function(fname)
        return lspconfig.util.find_git_ancestor(fname) or vim.fn.getcwd()
      end,
      settings = {},
    },
  }
end

-- Track if LSP attached
local lsp_attached = false

-- Setup LSP with callback
lspconfig.lex_lsp.setup({
  on_attach = function(client, bufnr)
    lsp_attached = true
  end,
})

-- Register .lex filetype
vim.filetype.add({
  extension = {
    lex = "lex",
  },
})

-- Open a table fixture
local test_file = plugin_dir .. "/comms/specs/elements/table.docs/table-01-flat-minimal.lex"
vim.cmd("edit " .. test_file)

-- Wait for LSP to attach (with timeout)
local max_wait = 5000
local waited = 0
local wait_step = 100

while not lsp_attached and waited < max_wait do
  vim.wait(wait_step)
  waited = waited + wait_step
end

if not lsp_attached then
  print("TEST_FAILED: LSP did not attach within timeout")
  vim.cmd("cquit 1")
end

-- Wait for LSP to be fully ready
vim.wait(500)

-- Request document symbols
local params = { textDocument = vim.lsp.util.make_text_document_params() }
local result = vim.lsp.buf_request_sync(0, 'textDocument/documentSymbol', params, 2000)

if not result or vim.tbl_isempty(result) then
  print("TEST_FAILED: No document symbols result returned from LSP")
  vim.cmd("cquit 1")
end

-- Helper to recursively find a symbol by name pattern
local function find_symbol(symbols, pattern)
  for _, symbol in ipairs(symbols) do
    if symbol.name and symbol.name:find(pattern) then
      return symbol
    end
    if symbol.children then
      local found = find_symbol(symbol.children, pattern)
      if found then return found end
    end
  end
  return nil
end

-- Extract symbols from result
local symbols = nil
for _, response in pairs(result) do
  if response.result and type(response.result) == "table" then
    symbols = response.result
    break
  end
end

if not symbols then
  print("TEST_FAILED: No symbols in LSP response")
  vim.cmd("cquit 1")
end

-- Find a table symbol
local table_symbol = find_symbol(symbols, "Table:")
if not table_symbol then
  print("TEST_FAILED: No table symbol found in outline")
  print("Available symbols:")
  for _, s in ipairs(symbols) do
    print("  " .. (s.name or "(unnamed)"))
  end
  vim.cmd("cquit 1")
end

print("Found table symbol: " .. table_symbol.name)

-- Table should have children (rows) — NOT be terminal
if not table_symbol.children or #table_symbol.children == 0 then
  print("TEST_FAILED: Table symbol has no children — table is terminal (should have Row children)")
  vim.cmd("cquit 1")
end

print("  Table has " .. #table_symbol.children .. " children")

-- Find a Row child
local row_symbol = find_symbol(table_symbol.children, "Row")
if not row_symbol then
  print("TEST_FAILED: Table has no Row children")
  vim.cmd("cquit 1")
end

print("  Found row: " .. row_symbol.name)

-- Row should have cell children
if not row_symbol.children or #row_symbol.children == 0 then
  print("TEST_FAILED: Row symbol has no children — should have Cell children")
  vim.cmd("cquit 1")
end

print("  Row has " .. #row_symbol.children .. " cell children")
for _, cell in ipairs(row_symbol.children) do
  print("    Cell: " .. (cell.name or "(unnamed)"))
end

print("TEST_PASSED: Table symbols include rows and cells as children (non-terminal)")
vim.cmd("qall!")
