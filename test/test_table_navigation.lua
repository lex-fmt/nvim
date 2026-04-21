-- Test: Table cell navigation via the LSP.
--
-- Since lexd-lsp v0.8.3 the pipe-counting logic lives in the server as
-- `lex.table.next_cell` / `lex.table.previous_cell`. The nvim plugin's
-- `navigate_table_cell` is a thin forwarder, so this test exercises it
-- end-to-end with a real LSP attached.

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

-- Create a buffer with table content as a real .lex file so the LSP attaches.
local tmp = vim.fn.tempname() .. ".lex"
local fh = io.open(tmp, "w")
if not fh then
  print("TEST_FAILED: could not write fixture to " .. tmp)
  vim.cmd("cquit 1")
end
fh:write("Table:\n    | Name  | Score |\n    | Alpha | 100   |\n    | Beta  | 200   |\n:: table ::\n")
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

-- Wait for didOpen to fully process on the server side.
vim.wait(300)

local ok, commands = pcall(require, "lex.commands")
if not ok then
  print("TEST_FAILED: could not load lex.commands: " .. tostring(commands))
  vim.cmd("cquit 1")
end

-- Pipes in "    | Name  | Score |" at columns 4, 12, 20 (0-indexed).
-- First cell content starts at col 6 (pipe+2 after col 4); second cell
-- content starts at col 14 (pipe+2 after col 12).
-- Table rows are on lines 2, 3, 4 (1-indexed) inside the buffer.

-- Test 1: next from first cell → second cell on same row.
vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- on "N" of "Name"
commands.navigate_table_cell("next")
local cursor = vim.api.nvim_win_get_cursor(0)
if cursor[1] ~= 2 or cursor[2] ~= 14 then
  print(string.format("TEST_FAILED: next within row expected (2, 14), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end
print("TEST_PASSED: next cell moves to second cell in same row")

-- Test 2: next from last cell wraps to first cell of next row.
vim.api.nvim_win_set_cursor(0, { 2, 14 }) -- on "Score" cell
commands.navigate_table_cell("next")
cursor = vim.api.nvim_win_get_cursor(0)
if cursor[1] ~= 3 or cursor[2] ~= 6 then
  print(string.format("TEST_FAILED: next wrap expected (3, 6), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end
print("TEST_PASSED: next cell wraps to first cell of next row")

-- Test 3: previous from second cell → first cell of same row.
vim.api.nvim_win_set_cursor(0, { 3, 14 }) -- on "100" cell
commands.navigate_table_cell("previous")
cursor = vim.api.nvim_win_get_cursor(0)
if cursor[1] ~= 3 or cursor[2] ~= 6 then
  print(string.format("TEST_FAILED: previous within row expected (3, 6), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end
print("TEST_PASSED: previous cell moves to first cell in same row")

-- Test 4: previous from first cell wraps to last cell of previous row.
vim.api.nvim_win_set_cursor(0, { 3, 6 })
commands.navigate_table_cell("previous")
cursor = vim.api.nvim_win_get_cursor(0)
if cursor[1] ~= 2 or cursor[2] ~= 14 then
  print(string.format("TEST_FAILED: previous wrap expected (2, 14), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end
print("TEST_PASSED: previous cell wraps to last cell of previous row")

os.remove(tmp)
print("TEST_PASSED: All table navigation tests passed")
vim.cmd("qall!")
