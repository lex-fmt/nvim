-- Regression test: opening a .lex document and attaching the LSP must
-- not emit any ERROR-level runtime messages.
--
-- The bug this guards against:
--   `vim.lsp.semantic_tokens.enable(true, { bufnr = bufnr, client_id = client.id })`
-- hard-errors on Neovim 0.12.1+ because `bufnr` and `client_id` are
-- mutually exclusive in the filter table. The error propagates through
-- Neovim's on_attach wrapper and surfaces via `vim.notify` with
-- `vim.log.levels.ERROR` (as `ON_ATTACH_ERROR: …`). Without a check on
-- those channels, the rest of on_attach silently fails to run (keymaps
-- don't bind, theme isn't applied, etc.) while feature tests that
-- assert only on protocol-level behaviour (e.g. "semantic tokens
-- arrive") still pass.
--
-- The guard intercepts `vim.notify(..., ERROR)` and
-- `vim.api.nvim_err_writeln` (see test/lex_test_utils.lua). This test
-- fails if either fires while a real .lex file is opened with the
-- plugin's own on_attach wired up via `minimal_init.lua`.

local script_path = debug.getinfo(1).source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

local lex_test_utils = require("lex_test_utils")

-- Do NOT re-run `lspconfig.lex_lsp.setup` here — that would replace the
-- plugin's own on_attach (which is what we actually want to exercise).
-- `minimal_init.lua` already calls `lex.setup(...)`, so opening a .lex
-- file is enough to trigger the real attach path.

local attached = false
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.name == "lex_lsp" then
      attached = true
    end
  end,
})

local tmp = vim.fn.tempname() .. ".lex"
local fh = io.open(tmp, "w")
if not fh then
  print("TEST_FAILED: could not write fixture to " .. tmp)
  vim.cmd("cquit 1")
end
fh:write("Document Title\n\n1. Section\n\n    A paragraph with a [reference].\n")
fh:close()

-- Reset any errors that may have accumulated during plugin loading;
-- we want to attribute only what fires during attach.
lex_test_utils.reset()

vim.cmd("edit " .. tmp)

local waited = 0
while not attached and waited < 5000 do
  vim.wait(100)
  waited = waited + 100
end

if not attached then
  print("TEST_FAILED: lex_lsp did not attach within 5s")
  vim.cmd("cquit 1")
end

-- Drain any async post-attach activity (semantic token requests,
-- diagnostics publish, etc.) so errors produced there are captured.
vim.wait(500)

lex_test_utils.assert_no_errors(
  "attaching lex_lsp to a .lex buffer produced runtime errors"
)

os.remove(tmp)
print("TEST_PASSED: no runtime errors emitted during LSP attach")
vim.cmd("qall!")
