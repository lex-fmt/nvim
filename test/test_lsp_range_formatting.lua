-- Test: range formatting via vim.lsp.buf.format({ range = ... }).
--
-- lex-lsp advertises documentRangeFormattingProvider, so Neovim's built-in
-- range format call should reach the server without any plugin glue.

local script_path = debug.getinfo(1).source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
if not lspconfig_ok then
  print("TEST_FAILED: lspconfig not available")
  vim.cmd("cquit 1")
end

local configs = require("lspconfig.configs")
local project_root = vim.fn.fnamemodify(plugin_dir, ":h:h")
local exe = vim.fn.exepath("lexd-lsp")
local lex_lsp_path = vim.env.LEX_LSP_PATH or (exe ~= "" and exe) or (project_root .. "/target/debug/lexd-lsp")

if vim.fn.filereadable(lex_lsp_path) ~= 1 then
  print("TEST_FAILED: lexd-lsp binary not found at " .. lex_lsp_path)
  vim.cmd("cquit 1")
end

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

local lsp_attached = false
lspconfig.lex_lsp.setup({
  on_attach = function()
    lsp_attached = true
  end,
})

vim.filetype.add({ extension = { lex = "lex" } })

-- Same messy fixture pattern used by test_lsp_formatting.lua: a definition
-- with misaligned list items and trailing whitespace is something the
-- formatter reliably rewrites.
local messy = {
  "Section One:",
  "",
  "  - fix me",
  "  -    also me",
  "",
  "",
}

local tmp = vim.fn.tempname() .. ".lex"
vim.fn.writefile(messy, tmp)
vim.cmd("edit " .. tmp)

local waited = 0
while not lsp_attached and waited < 5000 do
  vim.wait(100)
  waited = waited + 100
end

if not lsp_attached then
  print("TEST_FAILED: LSP did not attach")
  vim.cmd("cquit 1")
end

vim.wait(300)

local util = vim.lsp.util
local range_params = {
  textDocument = util.make_text_document_params(0),
  range = {
    start = { line = 0, character = 0 },
    ["end"] = { line = vim.api.nvim_buf_line_count(0) - 1, character = 0 },
  },
  options = { tabSize = 4, insertSpaces = true },
}

local result = vim.lsp.buf_request_sync(0, "textDocument/rangeFormatting", range_params, 5000)

if not result or vim.tbl_isempty(result) then
  print("TEST_FAILED: no response for textDocument/rangeFormatting")
  vim.cmd("cquit 1")
end

local edits = 0
for _, response in pairs(result) do
  if response.result and not vim.tbl_isempty(response.result) then
    edits = edits + #response.result
  end
end

if edits == 0 then
  print("TEST_FAILED: server returned no edits for range formatting")
  vim.cmd("cquit 1")
end

os.remove(tmp)
print("TEST_PASSED: range formatting forwards through the LSP")
vim.cmd("qall!")
