-- Test: `lex.setup({ format_on_save = true })` registers a BufWritePre
-- autocmd on the LexPlugin augroup; without the flag, no such autocmd is
-- registered. No LSP is required here — we only check autocmd wiring.

local script_path = debug.getinfo(1).source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

local function count_bufwritepre()
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, {
    group = "LexPlugin",
    event = "BufWritePre",
  })
  if not ok then
    return 0
  end
  return #autocmds
end

-- First call: no format_on_save → no BufWritePre entry on LexPlugin.
local lex = require("lex")
lex.setup({ cmd = { "/nonexistent-lsp-binary" } })
local before = count_bufwritepre()
if before ~= 0 then
  print(string.format(
    "TEST_FAILED: expected 0 BufWritePre autocmds without format_on_save, got %d",
    before
  ))
  vim.cmd("cquit 1")
end

-- Second call: format_on_save=true should add the autocmd.
lex.setup({ cmd = { "/nonexistent-lsp-binary" }, format_on_save = true })
local after = count_bufwritepre()
if after ~= 1 then
  print(string.format(
    "TEST_FAILED: expected exactly 1 BufWritePre autocmd with format_on_save, got %d",
    after
  ))
  vim.cmd("cquit 1")
end

print("TEST_PASSED: format_on_save opt-in registers a BufWritePre autocmd")
vim.cmd("qall!")
