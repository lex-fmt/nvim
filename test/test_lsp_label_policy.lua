-- Test: bare-as-blessed label policy surfaces through standard LSP.
--
-- Covers four behaviours that lex v0.13.0 (lex#584) ships through
-- standard LSP, with no nvim-side wiring:
--
--   1. Diagnostics — `:: doc.* ::` (×2) and unregistered `:: lex.X ::`
--      surface via `vim.diagnostic.get(0)` with codes
--      `forbidden-label-prefix` / `unknown-lex-canonical`.
--   2. Quickfix — code action provider returns a "Rewrite `doc.table` to
--      `table`" action for the curated mapping; the test applies it
--      and verifies the buffer line flips to `:: table ::`.
--   3. Hover — `:: title ::` (Shortcut), `:: metadata.author ::`
--      (Stripped), and `:: acme.task ::` (Community) each surface
--      their form-classification line through `textDocument/hover`.
--   4. Completion — typing `:: ` triggers a completion list that
--      includes blessed shortcuts (`table`, `image`, `video`, `audio`)
--      and never suggests reserved `doc.*`.

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
local lsp_client_id
lspconfig.lex_lsp.setup({
  on_attach = function(client)
    lsp_attached = true
    lsp_client_id = client.id
  end,
})

vim.filetype.add({ extension = { lex = "lex" } })

-- Mirror of the vscode fixture so the two suites stay in lock-step.
-- Lines (1-indexed):
--   1: header
--   2: ===
--   4: :: doc.table ::                  -- forbidden, curated quickfix
--   9: :: doc.unknownthing ::           -- forbidden, generic strip-fallback
--   12: :: lex.notarealsemantic ::      -- unknown-lex-canonical
--   15: :: title :: Example Doc         -- Shortcut form
--   17: :: metadata.author :: Alice     -- Stripped form
--   19: :: acme.task :: community shape -- Community form
local fixture = table.concat({
  "Label Policy Smoke",
  "==================",
  "",
  ":: doc.table ::",
  "    | h1 | h2 |",
  "    |----|----|",
  "    | a  | b  |",
  "",
  ":: doc.unknownthing ::",
  "    not a curated mapping; expect generic strip-fallback quickfix",
  "",
  ":: lex.notarealsemantic ::",
  "    not a registered canonical; expect unknown-lex-canonical diagnostic",
  "",
  ":: title :: Example Doc",
  "",
  ":: metadata.author :: Alice",
  "",
  ":: acme.task :: community shape",
  "",
  "A trailing paragraph so the parser sees a complete document.",
  "",
}, "\n")

local tmp = vim.fn.tempname() .. ".lex"
do
  local fh = io.open(tmp, "w")
  if not fh then
    print("TEST_FAILED: could not write fixture")
    vim.cmd("cquit 1")
  end
  fh:write(fixture)
  fh:close()
end

vim.cmd("edit " .. tmp)

local function wait_for(predicate, timeout_ms)
  local started = vim.loop.hrtime()
  while (vim.loop.hrtime() - started) / 1e6 < timeout_ms do
    if predicate() then return true end
    vim.cmd("sleep 50m")
  end
  return false
end

if not wait_for(function() return lsp_attached end, 5000) then
  print("TEST_FAILED: LSP did not attach within 5s")
  vim.cmd("cquit 1")
end

local bufnr = vim.api.nvim_get_current_buf()

-- ---------------------------------------------------------------------------
-- Sub-check 1: diagnostics
-- ---------------------------------------------------------------------------

local function diagnostic_code(d)
  if type(d.code) == "string" then return d.code end
  if type(d.code) == "number" then return tostring(d.code) end
  if type(d.user_data) == "table" and d.user_data.code then return tostring(d.user_data.code) end
  return ""
end

local function count_by_code(diags, code)
  local n = 0
  for _, d in ipairs(diags) do
    if diagnostic_code(d) == code then n = n + 1 end
  end
  return n
end

local diagnostics = {}
local got_expected = wait_for(function()
  diagnostics = vim.diagnostic.get(bufnr)
  return count_by_code(diagnostics, "forbidden-label-prefix") >= 2
    and count_by_code(diagnostics, "unknown-lex-canonical") >= 1
end, 5000)

if not got_expected then
  print("TEST_FAILED: expected diagnostics did not arrive; got:")
  for _, d in ipairs(diagnostics) do
    print(string.format("  code=%s  message=%s", tostring(d.code), tostring(d.message)))
  end
  vim.cmd("cquit 1")
end

-- The doc.table diagnostic should be attached to the `:: doc.table ::`
-- line (0-indexed line 3, since vim.diagnostic uses 0-based rows).
local doc_table_line = 3
local saw_doc_table = false
for _, d in ipairs(diagnostics) do
  if diagnostic_code(d) == "forbidden-label-prefix" and d.lnum == doc_table_line then
    saw_doc_table = true
    break
  end
end
if not saw_doc_table then
  print("TEST_FAILED: no forbidden-label-prefix diagnostic on line 3 (doc.table)")
  vim.cmd("cquit 1")
end

-- ---------------------------------------------------------------------------
-- Sub-check 2: quickfix
-- ---------------------------------------------------------------------------

local doc_table_diag
for _, d in ipairs(diagnostics) do
  if diagnostic_code(d) == "forbidden-label-prefix" and d.lnum == doc_table_line then
    doc_table_diag = d
    break
  end
end
assert(doc_table_diag, "doc.table diagnostic should be present")

local code_action_params = {
  textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  range = {
    start = { line = doc_table_diag.lnum, character = doc_table_diag.col },
    ["end"] = { line = doc_table_diag.end_lnum or doc_table_diag.lnum, character = doc_table_diag.end_col or 0 },
  },
  context = {
    diagnostics = { vim.diagnostic.get(bufnr)[1] and {
      range = {
        start = { line = doc_table_diag.lnum, character = doc_table_diag.col },
        ["end"] = { line = doc_table_diag.end_lnum or doc_table_diag.lnum, character = doc_table_diag.end_col or 0 },
      },
      severity = doc_table_diag.severity,
      code = doc_table_diag.code,
      message = doc_table_diag.message,
      source = doc_table_diag.source,
    } or {} },
    only = { "quickfix" },
  },
}

local ca_results = vim.lsp.buf_request_sync(bufnr, "textDocument/codeAction", code_action_params, 5000)
if not ca_results then
  print("TEST_FAILED: textDocument/codeAction request returned nil")
  vim.cmd("cquit 1")
end

local rewrite_action
for _, response in pairs(ca_results) do
  for _, action in ipairs(response.result or {}) do
    local title = (action.title or ""):lower()
    if title:find("rewrite") and title:find("table") then
      rewrite_action = action
      break
    end
  end
  if rewrite_action then break end
end

if not rewrite_action then
  print("TEST_FAILED: no 'Rewrite doc.table to table' code action; got:")
  for _, response in pairs(ca_results) do
    for _, action in ipairs(response.result or {}) do
      print("  - " .. tostring(action.title))
    end
  end
  vim.cmd("cquit 1")
end

-- Apply the action: prefer the inline edit (the canonical form for
-- label-policy quickfixes), fall back to command exec if the LSP
-- modelled it that way.
if rewrite_action.edit then
  vim.lsp.util.apply_workspace_edit(rewrite_action.edit, "utf-8")
elseif rewrite_action.command then
  vim.lsp.buf.execute_command(rewrite_action.command)
else
  print("TEST_FAILED: quickfix had neither edit nor command")
  vim.cmd("cquit 1")
end

local new_line = vim.api.nvim_buf_get_lines(bufnr, doc_table_line, doc_table_line + 1, false)[1] or ""
if not (new_line:find(":: table ::", 1, true) and not new_line:find("doc.table", 1, true)) then
  print("TEST_FAILED: expected line to become ':: table ::'; got: " .. new_line)
  vim.cmd("cquit 1")
end

-- Revert so the rest of the sub-checks see the original fixture.
vim.cmd("edit! " .. tmp)
bufnr = vim.api.nvim_get_current_buf()
-- Re-wait for diagnostics on the reloaded buffer so the hover/completion
-- checks below run against a settled LSP view.
if not wait_for(function()
  local ds = vim.diagnostic.get(bufnr)
  return count_by_code(ds, "forbidden-label-prefix") >= 2
end, 5000) then
  print("TEST_FAILED: diagnostics did not re-publish after revert")
  vim.cmd("cquit 1")
end

-- ---------------------------------------------------------------------------
-- Sub-check 3: hover form-classification
-- ---------------------------------------------------------------------------

-- (line index, expected substring)
local hover_cases = {
  { line = 14, search = ":: title ::", expect = "Shortcut for" },           -- 0-indexed line 14 = ":: title :: Example Doc"
  { line = 16, search = ":: metadata.author ::", expect = "Prefix-stripped form" },
  { line = 18, search = ":: acme.task ::", expect = "Community label" },
}

for _, case in ipairs(hover_cases) do
  local line_text = vim.api.nvim_buf_get_lines(bufnr, case.line, case.line + 1, false)[1] or ""
  if not line_text:find(case.search, 1, true) then
    print("TEST_FAILED: hover fixture line " .. case.line .. " did not contain '" .. case.search ..
          "', got: " .. line_text)
    vim.cmd("cquit 1")
  end
  -- Aim at the first character of the label (after `:: `).
  local label_col = (line_text:find(case.search, 1, true) - 1) + 3
  local hover_params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = case.line, character = label_col },
  }
  local hover_results = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", hover_params, 5000)
  local text = ""
  for _, response in pairs(hover_results or {}) do
    local contents = response.result and response.result.contents
    if contents then
      if type(contents) == "string" then
        text = text .. contents
      elseif type(contents) == "table" then
        if contents.value then
          text = text .. contents.value
        else
          for _, item in ipairs(contents) do
            if type(item) == "string" then
              text = text .. item
            elseif type(item) == "table" and item.value then
              text = text .. item.value
            end
          end
        end
      end
    end
  end
  if not text:find(case.expect, 1, true) then
    print("TEST_FAILED: hover on '" .. case.search .. "' did not include '" .. case.expect ..
          "'; got: " .. text)
    vim.cmd("cquit 1")
  end
end

-- ---------------------------------------------------------------------------
-- Sub-check 4: completion offers blessed shortcuts after `:: `
-- ---------------------------------------------------------------------------

-- Append a fresh `:: ` at the end of the buffer so the test doesn't
-- depend on cursor position vs other label sites.
local last_line = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "", ":: " })

-- Wait for the LSP to register the change.
vim.cmd("sleep 500m")

-- Trigger position: line is now last_line + 1 (0-indexed: last_line), col 3 (just after `:: `).
local trigger_line = last_line + 1
local completion_params = {
  textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  position = { line = trigger_line, character = 3 },
  context = { triggerKind = 2, triggerCharacter = " " },
}
local completion_results = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", completion_params, 5000)

local labels = {}
for _, response in pairs(completion_results or {}) do
  local result = response.result
  if result then
    local items = result.items or result
    for _, item in ipairs(items) do
      table.insert(labels, item.label or item.insertText or "")
    end
  end
end

local function has(label)
  for _, l in ipairs(labels) do
    if l == label then return true end
  end
  return false
end

for _, expected in ipairs({ "table", "image", "video", "audio" }) do
  if not has(expected) then
    print("TEST_FAILED: blessed shortcut '" .. expected .. "' missing from completions; got: " ..
          table.concat(labels, ", "))
    vim.cmd("cquit 1")
  end
end

for _, l in ipairs(labels) do
  if type(l) == "string" and l:sub(1, 4) == "doc." then
    print("TEST_FAILED: reserved doc.* label '" .. l .. "' was suggested; got: " ..
          table.concat(labels, ", "))
    vim.cmd("cquit 1")
  end
end

os.remove(tmp)
print("TEST_PASSED: label-policy LSP surface (diagnostics + quickfix + hover + completion)")
vim.cmd("qall!")
