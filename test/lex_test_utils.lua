-- Shared test utilities for Lex nvim e2e tests.
--
-- The main export here is an *error capture* shim. Neovim routes
-- errors triggered by plugin code through several channels, and
-- assertion-on-feature-output alone misses anything that lands on a
-- channel the test isn't watching. The concrete motivating incident:
-- `vim.lsp.semantic_tokens.enable(true, { bufnr, client_id })` hard-
-- errored on Neovim 0.12.1+ but the plugin's semantic-tokens test
-- still passed because protocol-level tokens kept flowing — the
-- error fired into `:messages` through a channel nobody was
-- watching.
--
-- This shim installs wrappers on the three practical channels:
--
--   1. `vim.notify(msg, vim.log.levels.ERROR, ...)` — modern plugin
--      code path.
--   2. `vim.api.nvim_err_writeln(msg)` — older low-level path and
--      `:echoerr` implementation.
--   3. `vim.api.nvim_echo(chunks, history, opts)` where opts.err is
--      truthy — the path Neovim's built-in LSP uses for
--      ON_ATTACH_ERROR and other client errors
--      (runtime/lua/vim/lsp/client.lua::err_message).
--
-- Tests call `assert_no_errors()` at the tail of their success path;
-- captured messages become a test failure.

local M = {}

M.captured_errors = {}

local function record(msg)
  table.insert(M.captured_errors, tostring(msg))
end

function M.install()
  if M._installed then
    return
  end
  M._installed = true

  local original_notify = vim.notify
  vim.notify = function(msg, level, opts)
    if level == vim.log.levels.ERROR then
      record(msg)
    end
    return original_notify(msg, level, opts)
  end

  local original_err_writeln = vim.api.nvim_err_writeln
  vim.api.nvim_err_writeln = function(msg)
    record(msg)
    return original_err_writeln(msg)
  end

  local original_echo = vim.api.nvim_echo
  vim.api.nvim_echo = function(chunks, history, opts)
    if opts and opts.err then
      for _, chunk in ipairs(chunks or {}) do
        if type(chunk) == "table" and chunk[1] then
          record(chunk[1])
        end
      end
    end
    return original_echo(chunks, history, opts)
  end
end

function M.reset()
  -- Clear in-place rather than reassigning so tests that hold a
  -- reference to `M.captured_errors` (e.g. closing over it before
  -- calling `reset()`) keep seeing newly-captured entries. Ignored
  -- patterns are configured globally and intentionally not reset.
  for i = #M.captured_errors, 1, -1 do
    M.captured_errors[i] = nil
  end
end

-- Ignore specific error messages that are known to be benign noise in
-- the test environment (e.g. unrelated LSPs complaining about missing
-- executables in CI). Pass a plain substring; matching is case-sensitive.
M.ignored_patterns = {}

function M.ignore(pattern)
  table.insert(M.ignored_patterns, pattern)
end

local function is_ignored(msg)
  for _, pattern in ipairs(M.ignored_patterns) do
    if msg:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

function M.has_errors()
  for _, msg in ipairs(M.captured_errors) do
    if not is_ignored(msg) then
      return true
    end
  end
  return false
end

-- Print all non-ignored captured errors and exit non-zero. Call at the
-- tail of a test's success path so any runtime error that fired during
-- the test is surfaced as a test failure instead of being silently
-- swallowed.
function M.assert_no_errors(context)
  local offenders = {}
  for _, msg in ipairs(M.captured_errors) do
    if not is_ignored(msg) then
      table.insert(offenders, msg)
    end
  end
  if #offenders > 0 then
    print(
      string.format(
        "TEST_FAILED: %s (%d runtime error%s captured):",
        context or "unexpected runtime errors during test",
        #offenders,
        #offenders == 1 and "" or "s"
      )
    )
    for i, err in ipairs(offenders) do
      print(string.format("  [%d] %s", i, err))
    end
    vim.cmd("cquit 1")
  end
end

return M
