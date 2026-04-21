-- Test: parser / footnote diagnostics surface on the buffer.
--
-- The server publishes diagnostics via standard `publishDiagnostics` for
-- MissingFootnoteDefinition / UnusedFootnoteDefinition / TableInconsistentColumns
-- (see crates/lex-lsp/src/server.rs). This test writes a fixture with a
-- dangling footnote reference and waits for the diagnostic to appear on
-- the buffer.

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

-- Fixture: referenced footnote [42] has no matching definition → the server
-- should publish a MissingFootnoteDefinition diagnostic.
local tmp = vim.fn.tempname() .. ".lex"
local fh = io.open(tmp, "w")
if not fh then
  print("TEST_FAILED: could not write fixture")
  vim.cmd("cquit 1")
end
fh:write("A paragraph referencing [42] which has no definition.\n")
fh:close()

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

-- Poll for diagnostics to land.
local diagnostics = {}
local poll_deadline = 5000
local polled = 0
while polled < poll_deadline do
  diagnostics = vim.diagnostic.get(0)
  if #diagnostics > 0 then
    break
  end
  vim.wait(100)
  polled = polled + 100
end

if #diagnostics == 0 then
  print("TEST_FAILED: no diagnostics published within " .. poll_deadline .. "ms")
  vim.cmd("cquit 1")
end

-- Confirm at least one carries a missing-footnote signal. The diagnostic's
-- `code` field ought to be "missing-footnote" per to_lsp_diagnostic.
local found = false
for _, d in ipairs(diagnostics) do
  if d.code == "missing-footnote" or (d.message and d.message:lower():find("footnote")) then
    found = true
    break
  end
end

if not found then
  print("TEST_FAILED: expected a missing-footnote diagnostic, got:")
  for _, d in ipairs(diagnostics) do
    print(string.format("  code=%s  message=%s", tostring(d.code), tostring(d.message)))
  end
  vim.cmd("cquit 1")
end

os.remove(tmp)
print("TEST_PASSED: parser/footnote diagnostics surface on the buffer")
vim.cmd("qall!")
