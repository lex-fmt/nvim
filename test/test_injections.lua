-- Test: Tree-sitter injection highlighting for verbatim blocks
--
-- Verifies that verbatim blocks with language annotations (:: python ::)
-- are detected as injection zones by the tree-sitter query.

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

-- Open the injection fixture
vim.filetype.add({ extension = { lex = "lex" } })
local fixture = plugin_dir .. "/comms/specs/benchmark/060-injection-multilang.lex"
vim.cmd("edit " .. fixture)
vim.wait(100)

-- Parse the file
local parser_ok, parser = pcall(vim.treesitter.get_parser, 0, "lex")
if not parser_ok or not parser then
  print("TEST_FAILED: Could not get parser: " .. tostring(parser))
  vim.cmd("cquit 1")
end

local tree = parser:parse()[1]
local root = tree:root()

print("TEST_PASSED: Injection fixture parsed, root: " .. root:type())

-- Test 1: Find verbatim_block nodes in the tree
local verbatim_count = 0
local function count_verbatim(node)
  if node:type() == "verbatim_block" then
    verbatim_count = verbatim_count + 1
  end
  for child in node:iter_children() do
    count_verbatim(child)
  end
end
count_verbatim(root)

if verbatim_count < 4 then
  print("TEST_FAILED: Expected at least 4 verbatim blocks, found " .. verbatim_count)
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Found " .. verbatim_count .. " verbatim blocks")

-- Test 2: Verify injection query loads
local query_ok, injection_query = pcall(vim.treesitter.query.get, "lex", "injections")
if not query_ok or not injection_query then
  print("TEST_FAILED: Could not load injection query: " .. tostring(injection_query))
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Injection query loaded")

-- Test 3: Run injection query and check for matches
local injection_langs = {}
for _, match, metadata in injection_query:iter_matches(root, 0) do
  for id, nodes in pairs(match) do
    local name = injection_query.captures[id]
    if name == "injection.language" then
      -- nodes can be a single node or a table of nodes
      local node = type(nodes) == "table" and nodes[1] or nodes
      local text = vim.treesitter.get_node_text(node, 0)
      -- The #gsub! directive strips parameters, but we can check raw text
      local lang = text:match("^%s*(%S+)")
      if lang then
        injection_langs[lang] = true
      end
    end
  end
end

if not injection_langs["python"] then
  print("TEST_FAILED: No python injection detected")
  vim.cmd("cquit 1")
end

if not injection_langs["json"] then
  print("TEST_FAILED: No json injection detected")
  vim.cmd("cquit 1")
end

if not injection_langs["bash"] then
  print("TEST_FAILED: No bash injection detected (verbatim group)")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Injection zones detected: python, json, bash (group)")

-- Test 4: Verify no ERROR nodes in the fixture
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
  print("TEST_FAILED: Injection fixture has parse errors")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: No parse errors in injection fixture")

print("TEST_PASSED: All injection tests passed")
vim.cmd("qall!")
