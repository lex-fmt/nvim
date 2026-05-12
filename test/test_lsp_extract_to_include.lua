-- Test: :LexExtractToInclude splits a selection into a new include file
-- and replaces the host range with `:: lex.include src="..." ::`.
--
-- Covers:
--   1. Happy path — visual selection extracts into target.
--   2. Validation error — invalid src surfaces the server's typed
--      `ExtractError` message via `vim.notify`.
--   3. No-selection guard — running without a range refuses up front
--      (the `'<`/`'>` marks from a prior visual select don't leak).

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

-- Tempdir + host file. The target ends up alongside the host in the same
-- temp directory; that's where the LSP resolves `src` relative to.
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local host_path = tmpdir .. "/host.lex"
local target_path = tmpdir .. "/extracted.lex"
local host_text = "Doc\n===\n\nIntro paragraph.\n\nSection A:\n    First body line.\n    Second body line.\n\nAfter section.\n"
local fh = io.open(host_path, "w")
if not fh then
  print("TEST_FAILED: could not write host fixture")
  vim.cmd("cquit 1")
end
fh:write(host_text)
fh:close()

vim.cmd("edit " .. host_path)
vim.cmd("setfiletype lex")

require("lex").setup({})

local function wait_for(predicate, timeout_ms)
  local started = vim.loop.hrtime()
  while (vim.loop.hrtime() - started) / 1e6 < timeout_ms do
    if predicate() then return true end
    vim.cmd("sleep 50m")
  end
  return false
end

if not wait_for(function() return lsp_attached end, 10000) then
  print("TEST_FAILED: LSP did not attach within 10s")
  vim.cmd("cquit 1")
end
-- Extra settle for the server to finish boot before we hammer it with
-- executeCommand. Mirrors the wait pattern used by sibling LSP tests.
vim.cmd("sleep 500m")

-- Stub vim.ui.input so the test drives the prompt without a real UI.
local function stub_ui_input(value)
  vim.ui.input = function(_opts, cb)
    cb(value)
  end
end

-- Capture vim.notify so we can assert on the user-visible message.
local last_notify = { msg = nil, level = nil }
vim.notify = function(msg, level)
  last_notify = { msg = msg, level = level }
end

-- ── Case 1: happy path — extract the indented body of "Section A:" into
-- ── extracted.lex; expect the host buffer to gain `:: lex.include ::` and
-- ── the on-disk target to hold the indent-shifted body.
--
-- Headless nvim doesn't let us actually drive visual mode the way an
-- interactive user would (the `normal! v…` dance leaves the buffer in
-- visual mode and `'<,'>` aren't reliably set). Setting the visual marks
-- directly via `nvim_buf_set_mark` and calling the handler with
-- `{ range = 2 }` simulates the same entry point that
-- `:'<,'>LexExtractToInclude` would.
vim.api.nvim_buf_set_mark(0, "<", 7, 4, {}) -- line 7, col 5 → 0-indexed col 4
vim.api.nvim_buf_set_mark(0, ">", 8, 22, {}) -- line 8, end-ish
stub_ui_input("extracted.lex")
require("lex.commands").extract_to_include({ range = 2 })
-- Wait for the apply_workspace_edit + IPC + reload to settle.
if not wait_for(function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:find("lex.include src=", 1, true) then return true end
  end
  return false
end, 5000) then
  print("TEST_FAILED: host buffer did not gain the include annotation")
  print("  buffer:")
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    print("    " .. line)
  end
  vim.cmd("cquit 1")
end

if vim.fn.filereadable(target_path) ~= 1 then
  print("TEST_FAILED: target file was not created at " .. target_path)
  vim.cmd("cquit 1")
end
local target_fh = io.open(target_path, "r")
local target_text = target_fh and target_fh:read("*a") or ""
if target_fh then target_fh:close() end
if not target_text:find("First body line.", 1, true) then
  print("TEST_FAILED: target text missing extracted body lines")
  print("  got: " .. vim.inspect(target_text))
  vim.cmd("cquit 1")
end

-- ── Case 2: validation error — invalid src (URL scheme) surfaces the
-- ── server's typed ExtractError via vim.notify.
-- `edit!` forces a reload — the case-1 buffer has the include annotation
-- applied but wasn't saved, and a plain `:edit` would refuse.
vim.cmd("edit! " .. host_path)
vim.api.nvim_buf_set_mark(0, "<", 4, 0, {})
vim.api.nvim_buf_set_mark(0, ">", 4, 15, {})
stub_ui_input("https://elsewhere/foo.lex")
last_notify = { msg = nil, level = nil }
require("lex.commands").extract_to_include({ range = 2 })
if not wait_for(function() return last_notify.msg ~= nil end, 5000) then
  print("TEST_FAILED: expected vim.notify call for URL-scheme rejection")
  vim.cmd("cquit 1")
end
if not last_notify.msg or not last_notify.msg:lower():find("url") then
  print("TEST_FAILED: expected URL-scheme error message, got: " .. tostring(last_notify.msg))
  vim.cmd("cquit 1")
end
if last_notify.level ~= vim.log.levels.ERROR then
  print("TEST_FAILED: expected ERROR level on validation failure, got: " .. tostring(last_notify.level))
  vim.cmd("cquit 1")
end

-- ── Case 3: no-range guard — invoking without a visual range refuses up
-- ── front (even if stale `'<`/`'>` marks from prior selections exist).
last_notify = { msg = nil, level = nil }
require("lex.commands").extract_to_include({ range = 0 })
if not last_notify.msg or not last_notify.msg:find("visual selection", 1, true) then
  print("TEST_FAILED: expected refusal message when range == 0, got: " .. tostring(last_notify.msg))
  vim.cmd("cquit 1")
end

print("TEST_PASSED")
vim.cmd("qall!")
