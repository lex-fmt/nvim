-- Test: Table blocks parse correctly and are NOT injected as a language
--
-- Verifies that:
-- 1. Table blocks (:: table ::) parse as verbatim_block without errors
-- 2. Table blocks are NOT treated as language injections
-- 3. Table caption (subject) gets heading highlight, not raw block
-- 4. Table closing annotation gets keyword highlight, not comment

local script_path = debug.getinfo(1).source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

-- Check for C compiler
local cc = vim.env.CC or "cc"
if vim.fn.executable(cc) ~= 1 then
  print("TEST_SKIPPED: No C compiler found (" .. cc .. ")")
  vim.cmd("qall!")
end

-- Resolve tree-sitter source path
local ts_path = vim.env.LEX_TREESITTER_PATH
if not ts_path or ts_path == "" then
  local workspace_root = vim.fn.fnamemodify(plugin_dir, ":h")
  local core_ts = workspace_root .. "/core/tree-sitter"
  if vim.fn.isdirectory(core_ts) == 1 then
    ts_path = core_ts
  end
end

if not ts_path then
  print("TEST_SKIPPED: No tree-sitter source path (set LEX_TREESITTER_PATH)")
  vim.cmd("qall!")
end

-- Compile and register parser
local ts = require("lex.treesitter")
local so_path, err = ts.ensure_parser({ path = ts_path })
if not so_path then
  print("TEST_FAILED: Could not compile parser: " .. tostring(err))
  vim.cmd("cquit 1")
end

vim.treesitter.language.add("lex", { path = so_path })

-- Create a buffer with table content
vim.filetype.add({ extension = { lex = "lex" } })
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "lex"

local table_content = {
  "Results:",
  "    | Name  | Score |",
  "    | Alpha | 100   |",
  "    | Beta  | 200   |",
  ":: table header=1 ::",
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, table_content)
vim.wait(100)

-- Test 1: Parse the buffer
local parser_ok, parser = pcall(vim.treesitter.get_parser, buf, "lex")
if not parser_ok or not parser then
  print("TEST_FAILED: Could not get parser: " .. tostring(parser))
  vim.cmd("cquit 1")
end

local tree = parser:parse()[1]
local root = tree:root()

-- Check for ERROR nodes
local has_error = false
local function check_errors(node)
  if node:type() == "ERROR" then
    has_error = true
    local sr, sc = node:range()
    print("  ERROR at line " .. (sr + 1) .. ":" .. sc)
  end
  for child in node:iter_children() do
    check_errors(child)
  end
end
check_errors(root)

if has_error then
  print("TEST_FAILED: Table content has parse errors")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Table content parsed without errors")

-- Test 2: Verify table parses as verbatim_block
local found_verbatim = false
local function find_verbatim(node)
  if node:type() == "verbatim_block" then
    found_verbatim = true
  end
  for child in node:iter_children() do
    find_verbatim(child)
  end
end
find_verbatim(root)

if not found_verbatim then
  print("TEST_FAILED: Table did not parse as verbatim_block")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Table parsed as verbatim_block")

-- Test 3: Verify table blocks are NOT in injection results
local query_ok, injection_query = pcall(vim.treesitter.query.get, "lex", "injections")
if not query_ok or not injection_query then
  print("TEST_FAILED: Could not load injection query: " .. tostring(injection_query))
  vim.cmd("cquit 1")
end

local injection_langs = {}
for _, match in injection_query:iter_matches(root, buf) do
  for id, nodes in pairs(match) do
    local name = injection_query.captures[id]
    if name == "injection.language" then
      local node = type(nodes) == "table" and nodes[1] or nodes
      local text = vim.treesitter.get_node_text(node, buf)
      local lang = text:match("^%s*(%S+)")
      if lang then
        injection_langs[lang] = true
      end
    end
  end
end

if injection_langs["table"] then
  print("TEST_FAILED: Table block was incorrectly detected as injection language")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Table block excluded from injection detection")

-- Test 4: Verify highlight query captures table elements correctly
local hl_ok, highlight_query = pcall(vim.treesitter.query.get, "lex", "highlights")
if not hl_ok or not highlight_query then
  print("TEST_FAILED: Could not load highlight query: " .. tostring(highlight_query))
  vim.cmd("cquit 1")
end

local captures_by_name = {}
for id, node in highlight_query:iter_captures(root, buf) do
  local name = highlight_query.captures[id]
  if not captures_by_name[name] then
    captures_by_name[name] = {}
  end
  table.insert(captures_by_name[name], vim.treesitter.get_node_text(node, buf))
end

-- Table subject should be captured as markup.heading (from table override)
if not captures_by_name["markup.heading"] then
  print("TEST_FAILED: No markup.heading capture found (expected table caption)")
  vim.cmd("cquit 1")
end

local has_caption = false
for _, text in ipairs(captures_by_name["markup.heading"] or {}) do
  if text:match("Results") then
    has_caption = true
  end
end

if not has_caption then
  print("TEST_FAILED: Table caption not captured as markup.heading")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Table caption highlighted as markup.heading")

-- Table closing annotation should be captured as keyword (from table override)
if not captures_by_name["keyword"] then
  print("TEST_FAILED: No keyword capture found (expected table closing annotation)")
  vim.cmd("cquit 1")
end

local has_keyword = false
for _, text in ipairs(captures_by_name["keyword"] or {}) do
  if text:match("table") then
    has_keyword = true
  end
end

if not has_keyword then
  print("TEST_FAILED: Table closing annotation not captured as keyword")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Table closing annotation highlighted as keyword")

-- Test 5: Verify pipe delimiters are captured as punctuation.delimiter
local has_pipe_delimiter = false
for _, text in ipairs(captures_by_name["punctuation.delimiter"] or {}) do
  if text == "|" then
    has_pipe_delimiter = true
  end
end

if not has_pipe_delimiter then
  print("TEST_FAILED: Pipe delimiters not captured as punctuation.delimiter")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Pipe delimiters highlighted as punctuation.delimiter")

-- Test 6: Verify with a real fixture that has tables
local fixture = plugin_dir .. "/comms/specs/benchmark/080-gentle-introduction.lex"
if vim.fn.filereadable(fixture) == 1 then
  vim.cmd("edit " .. fixture)
  vim.wait(100)

  local fix_parser = vim.treesitter.get_parser(0, "lex")
  local fix_tree = fix_parser:parse()[1]
  local fix_root = fix_tree:root()

  local fix_errors = false
  local function check_fix_errors(node)
    if node:type() == "ERROR" then
      fix_errors = true
    end
    for child in node:iter_children() do
      check_fix_errors(child)
    end
  end
  check_fix_errors(fix_root)

  if fix_errors then
    print("TEST_FAILED: Fixture 080-gentle-introduction.lex has parse errors")
    vim.cmd("cquit 1")
  end

  -- Check that table injection is excluded in the fixture too
  local fix_inj_langs = {}
  for _, match in injection_query:iter_matches(fix_root, 0) do
    for id, nodes in pairs(match) do
      local name = injection_query.captures[id]
      if name == "injection.language" then
        local node = type(nodes) == "table" and nodes[1] or nodes
        local text = vim.treesitter.get_node_text(node, 0)
        local lang = text:match("^%s*(%S+)")
        if lang then
          fix_inj_langs[lang] = true
        end
      end
    end
  end

  if fix_inj_langs["table"] then
    print("TEST_FAILED: Fixture table block incorrectly detected as injection")
    vim.cmd("cquit 1")
  end

  print("TEST_PASSED: Fixture parsed and table injection correctly excluded")
else
  print("TEST_SKIPPED: Fixture 080-gentle-introduction.lex not found")
end

print("TEST_PASSED: All table highlighting tests passed")
vim.cmd("qall!")
