-- Test: LexReorderFootnotes renumbers footnote refs + definitions.

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

local tmp = vim.fn.tempname() .. ".lex"
local fh = io.open(tmp, "w")
if not fh then
  print("TEST_FAILED: could not write fixture")
  vim.cmd("cquit 1")
end
-- Two footnote refs in reverse numeric order ([2] then [1]) plus their
-- definitions. The reorder command should rewrite the references so the
-- first appearing is [1] and the second is [2].
fh:write("Intro with refs [2] and [1].\n\n:: notes ::\n1. First\n2. Second\n")
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

vim.wait(300)

local ok, commands = pcall(require, "lex.commands")
if not ok then
  print("TEST_FAILED: could not load lex.commands")
  vim.cmd("cquit 1")
end

commands.reorder_footnotes()

local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
-- Post-reorder the first-appearing reference must be [1] and the second
-- must be [2]; since we originally had [2] first and [1] second, that
-- means the numbers are swapped in the text.
if not content:match("%[1%].-%[2%]") then
  print("TEST_FAILED: reorder_footnotes did not produce expected order")
  print("content:\n" .. content)
  vim.cmd("cquit 1")
end

os.remove(tmp)
print("TEST_PASSED: reorder_footnotes renumbers footnote references")
vim.cmd("qall!")
