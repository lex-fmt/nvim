-- Lex Neovim Plugin - Smart Paste
-- ===============================
--
-- Editor-side glue for smart paste (issue #82, spec comms#73
-- `specs/proposals/smart-paste.lex` §1, §5). All transform logic lives
-- server-side in lexd-lsp behind the custom `lex/preparePaste` request; this
-- module is the thin capture-and-apply shim.
--
-- Lex encodes document structure as indentation, so clipboard text carries the
-- *absolute* indentation of wherever it was copied and arrives mis-indented
-- when dropped elsewhere. On paste into a `.lex` buffer we hand the raw
-- clipboard text plus the caret/selection range to the server, which re-anchors
-- it to the caret's structural context, and we splice the returned `text` in.
--
-- The seam is `vim.paste`: Neovim routes every paste path through it (`p`/`P`,
-- bracketed paste, `:put`, the `"+`/`"*` registers). `vim.paste` is a single
-- global with no buffer-local dispatch, so we override it once, wrap the
-- original as the fallback, and only intercept when the target buffer has a
-- `lex_lsp` client advertising the capability. Every other buffer — and lex
-- buffers without a capable server — falls straight through to native paste,
-- so nothing changes elsewhere.

local M = {}

-- The custom LSP request method (matches lexd-lsp's tower-lsp wiring).
local PREPARE_PASTE = "lex/preparePaste"

-- The native paste handler we wrap. Captured at install time; nil until
-- `M.setup()` runs.
local native_paste = nil

-- Find the lexd-lsp client attached to `bufnr` that advertises the smart-paste
-- capability. lexd-lsp advertises it under `experimental.lexPreparePaste`
-- (server.rs: `experimental: { "lexPreparePaste": true }`). Returns nil when no
-- such client is attached, which is the signal to fall back to native paste.
local function get_capable_client(bufnr)
  local clients = vim.lsp.get_clients({ name = "lex_lsp", bufnr = bufnr })
  for _, client in ipairs(clients) do
    local experimental = client.server_capabilities
      and client.server_capabilities.experimental
    if experimental and experimental.lexPreparePaste then
      return client
    end
  end
  return nil
end

-- Build the LSP Range the paste replaces. Its *start* is the structural anchor
-- the server re-anchors against (prepare_paste.rs: "its start is the structural
-- anchor"). `vim.paste` runs after Neovim has established where the paste lands,
-- so the cursor is the anchor; we emit an empty range there. Columns are byte
-- offsets, matching lexd-lsp's UTF-8 column convention (same as the rest of
-- this plugin's LSP glue).
local function cursor_range()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = { line = cursor[1] - 1, character = cursor[2] }
  return { start = pos, ["end"] = pos }
end

-- Ask the server to re-anchor `pasted_text`. Returns the transformed string, or
-- nil if the request fails / times out (caller falls back to the raw text).
local function prepare(client, bufnr, pasted_text)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    range = cursor_range(),
    pastedText = pasted_text,
  }

  -- Synchronous-by-waiting request scoped to *this* client only. `vim.paste`
  -- is called inline on the paste keystroke, so we cannot defer; we issue the
  -- async `client:request` and pump the loop with `vim.wait` until it answers
  -- or the 1s budget elapses. A slow/hung server must not wedge the editor —
  -- on timeout we cancel and fall through to native paste.
  --
  -- We deliberately do NOT use `vim.lsp.buf_request_sync`: it broadcasts the
  -- custom `lex/preparePaste` method to every client attached to the buffer
  -- and waits on all of them, so an unrelated LSP that doesn't implement it
  -- could burn the whole timeout. We already resolved the target `client`, so
  -- query only it.
  local done, response
  local ok, request_id = client:request(PREPARE_PASTE, params, function(err, result)
    done = true
    response = { err = err, result = result }
  end, bufnr)

  if not ok then
    return nil
  end

  if not vim.wait(1000, function() return done end, 10) then
    -- Timed out: cancel the in-flight request so the handler can't fire late.
    if request_id then
      pcall(function() client:cancel_request(request_id) end)
    end
    return nil
  end

  if not response or response.err or type(response.result) ~= "table" then
    return nil
  end
  local result = response.result
  if type(result.text) ~= "string" then
    return nil
  end
  return result.text
end

-- The global `vim.paste` replacement.
--
-- `lines` is the clipboard split on newlines (Neovim's `vim.paste` contract);
-- `phase` is -1 for a non-chunked paste, or 1..3 for the start/middle/end of a
-- chunked (large) bracketed paste; `opts` is the (currently sparse) paste
-- context table Neovim may pass. We only transform a complete, single-shot
-- paste (`phase == -1`) into a capable lex buffer: a chunked paste has no
-- whole-clipboard view to re-anchor, and the server transform is whole-text.
-- Everything else (other filetypes, no client, no capability, chunked, empty)
-- defers to the captured native handler unchanged.
--
-- `opts` is accepted and forwarded verbatim on every path so the native handler
-- always receives the same paste context it would without the shim, preserving
-- the full `vim.paste(lines, phase, opts)` contract.
local function smart_paste(lines, phase, opts)
  local bufnr = vim.api.nvim_get_current_buf()

  if phase ~= -1 then
    return native_paste(lines, phase, opts)
  end

  local client = get_capable_client(bufnr)
  if not client then
    return native_paste(lines, phase, opts)
  end

  -- Reconstruct the raw clipboard text. `vim.paste` already stripped the
  -- newlines into list elements; rejoin with "\n" so the server sees the
  -- clipboard verbatim (the transform owns indentation, not us).
  local pasted_text = table.concat(lines, "\n")
  if pasted_text == "" then
    return native_paste(lines, phase, opts)
  end

  local transformed = prepare(client, bufnr, pasted_text)
  if transformed == nil then
    -- Request failed/timed out — native paste with the original text.
    return native_paste(lines, phase, opts)
  end

  -- Splice the re-anchored text in via the native handler so cursor
  -- placement, undo blocks, and register semantics stay Neovim's job.
  return native_paste(vim.split(transformed, "\n", { plain = true }), phase, opts)
end

-- Install the smart-paste override. Idempotent: a second call is a no-op (we
-- only capture `native_paste` once, so re-running setup never wraps our own
-- handler around itself).
function M.setup()
  if native_paste ~= nil then
    return
  end
  native_paste = vim.paste
  vim.paste = smart_paste
end

return M
