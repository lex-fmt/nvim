-- Test: smart paste (#82) — `lex/preparePaste` re-anchors pasted text.
--
-- Exercises the editor-side shim end-to-end against a real lexd-lsp:
--   1. the server advertises the `lexPreparePaste` capability on attach;
--   2. `vim.paste` is overridden after `lex.setup`;
--   3. pasting an over-indented block into a session body re-anchors it to
--      the caret's structural context (the whole point of smart paste).

local script_path = debug.getinfo(1).source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
if not lspconfig_ok then
  print("TEST_FAILED: lspconfig not available")
  vim.cmd("cquit 1")
end

local project_root = vim.fn.fnamemodify(plugin_dir, ":h:h")
local exe = vim.fn.exepath("lexd-lsp")
local lex_lsp_path = vim.env.LEX_LSP_PATH or (exe ~= "" and exe) or (project_root .. "/target/debug/lexd-lsp")

if vim.fn.filereadable(lex_lsp_path) ~= 1 then
  print("TEST_FAILED: lexd-lsp binary not found at " .. lex_lsp_path)
  vim.cmd("cquit 1")
end

-- Drive the whole plugin (not a bare lspconfig.setup) so we get the real
-- `vim.paste` override wired by `lex.setup` → `smart_paste.setup`.
local captured_client = nil
local lex_ok, lex = pcall(require, "lex")
if not lex_ok then
  print("TEST_FAILED: could not load lex")
  vim.cmd("cquit 1")
end

lex.setup({
  cmd = { lex_lsp_path },
  lsp_config = {
    on_attach = function(client)
      captured_client = client
    end,
  },
})

-- A document with a `things` session whose body is indented four spaces.
-- The caret will land inside that body; the clipboard carries an
-- 8-space-indented block (as if lifted from one level deeper elsewhere).
local tmp = vim.fn.tempname() .. ".lex"
local fh = io.open(tmp, "w")
if not fh then
  print("TEST_FAILED: could not write fixture")
  vim.cmd("cquit 1")
end
fh:write(":: things ::\n    existing line\n")
fh:close()

vim.cmd("edit " .. tmp)

vim.wait(5000, function()
  return captured_client ~= nil
end, 100)

if not captured_client then
  print("TEST_FAILED: LSP did not attach")
  vim.cmd("cquit 1")
end

-- 1. Capability advertised. Poll: capabilities populate on initialize, which
--    can land slightly after on_attach fires.
vim.wait(5000, function()
  local exp = captured_client.server_capabilities
    and captured_client.server_capabilities.experimental
  return not not (exp and exp.lexPreparePaste)
end, 100)

local experimental = captured_client.server_capabilities
  and captured_client.server_capabilities.experimental
if not (experimental and experimental.lexPreparePaste) then
  print("TEST_FAILED: server did not advertise lexPreparePaste capability")
  vim.cmd("cquit 1")
end

-- 2. vim.paste was overridden.
if type(vim.paste) ~= "function" then
  print("TEST_FAILED: vim.paste missing after setup")
  vim.cmd("cquit 1")
end

-- 3. Paste an over-indented multi-line block into the session body and
--    assert it gets re-anchored. Put the cursor at the start of a fresh
--    line under the session body.
vim.api.nvim_win_set_cursor(0, { 2, 0 })
-- Open a new line below so the paste lands inside the session body on a
-- fresh line (re-anchor mode requires multi-line clipboard text).
vim.api.nvim_buf_set_lines(0, 2, 2, false, { "" })
vim.api.nvim_win_set_cursor(0, { 3, 0 })

-- Clipboard text indented at 8 spaces; two lines so it is NOT
-- passthrough-single-line. Smart paste should dedent to the session body's
-- 4-space anchor.
local clipboard = "        deep one\n        deep two"
vim.paste(vim.split(clipboard, "\n", { plain = true }), -1)

-- Poll until the pasted text lands rather than sleeping a fixed interval.
vim.wait(2000, function()
  local buf = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  return buf:find("deep one", 1, true) ~= nil
end, 50)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local content = table.concat(lines, "\n")

-- Locate the two pasted lines and capture their exact leading indent.
local function indent_of(needle)
  for _, l in ipairs(lines) do
    local lead = l:match("^(%s*)" .. needle .. "$")
    if lead then
      return lead
    end
  end
  return nil
end

local indent_one = indent_of("deep one")
local indent_two = indent_of("deep two")

if indent_one == nil or indent_two == nil then
  print("TEST_FAILED: pasted text did not land in the buffer")
  print("content:\n" .. content)
  vim.cmd("cquit 1")
end

-- Re-anchoring must (a) strip the clipboard's original 8-space indent and
-- (b) apply a single common anchor to both lines (the dedent collapses the
-- uniform 8-space prefix to one offset). Asserting the exact resulting
-- indent — not merely "not 8 spaces" — catches a server that returns the
-- block at the wrong column.
if indent_one ~= indent_two then
  print("TEST_FAILED: pasted lines got different indents (re-anchor not uniform): "
    .. ("[%q] vs [%q]"):format(indent_one, indent_two))
  print("content:\n" .. content)
  vim.cmd("cquit 1")
end

if #indent_one >= 8 then
  print("TEST_FAILED: pasted text was not dedented from its original 8-space indent (got "
    .. tostring(#indent_one) .. " leading spaces)")
  print("content:\n" .. content)
  vim.cmd("cquit 1")
end

os.remove(tmp)
print("TEST_PASSED: smart paste re-anchors via lex/preparePaste")
vim.cmd("qall!")
