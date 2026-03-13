-- Test: Tree-sitter parser loads and highlights lex files
--
-- Verifies that the tree-sitter parser can be compiled from source,
-- registered with Neovim, and used to parse a .lex file without errors.

local script_path = debug.getinfo(1).source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

-- Check that a C compiler is available
local cc = vim.env.CC or "cc"
if vim.fn.executable(cc) ~= 1 then
  print("TEST_SKIPPED: No C compiler found (" .. cc .. ")")
  vim.cmd("qall!")
end

-- Load the treesitter module directly
local ok, ts = pcall(require, "lex.treesitter")
if not ok then
  print("TEST_FAILED: Could not load lex.treesitter module: " .. tostring(ts))
  vim.cmd("cquit 1")
end

-- Test 1: Compile parser from local core tree-sitter source
-- Use LEX_TREESITTER_PATH env var or try standard location
local ts_path = vim.env.LEX_TREESITTER_PATH
if not ts_path or ts_path == "" then
  -- Try the standard workspace layout
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

local so_path, err = ts.ensure_parser({ path = ts_path })
if not so_path then
  print("TEST_FAILED: Could not compile parser: " .. tostring(err))
  vim.cmd("cquit 1")
end

if vim.fn.filereadable(so_path) ~= 1 then
  print("TEST_FAILED: Compiled .so not found at " .. so_path)
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Parser compiled successfully to " .. so_path)

-- Test 2: Register parser with Neovim
local reg_ok, reg_err = pcall(vim.treesitter.language.add, "lex", { path = so_path })
if not reg_ok then
  print("TEST_FAILED: Could not register parser: " .. tostring(reg_err))
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Parser registered with Neovim")

-- Test 3: Parse a fixture file and check for errors
vim.filetype.add({ extension = { lex = "lex" } })
local fixture = plugin_dir .. "/comms/specs/benchmark/050-lsp-fixture.lex"
vim.cmd("edit " .. fixture)
vim.wait(100)

local parser_ok, parser = pcall(vim.treesitter.get_parser, 0, "lex")
if not parser_ok or not parser then
  print("TEST_FAILED: Could not get parser for buffer: " .. tostring(parser))
  vim.cmd("cquit 1")
end

local tree = parser:parse()[1]
if not tree then
  print("TEST_FAILED: Parser returned no tree")
  vim.cmd("cquit 1")
end

local root = tree:root()
if not root then
  print("TEST_FAILED: Tree has no root node")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: Parsed fixture, root type: " .. root:type())

-- Test 4: Walk tree and check for ERROR nodes
local has_error = false
local function walk(node)
  if node:type() == "ERROR" then
    has_error = true
    local sr, sc, er, ec = node:range()
    print("  ERROR node at " .. sr .. ":" .. sc .. "-" .. er .. ":" .. ec)
  end
  for child in node:iter_children() do
    walk(child)
  end
end
walk(root)

if has_error then
  print("TEST_FAILED: Tree contains ERROR nodes")
  vim.cmd("cquit 1")
end

print("TEST_PASSED: No ERROR nodes in parsed tree")

-- Test 5: Enable tree-sitter highlighting
vim.treesitter.start(0, "lex")
print("TEST_PASSED: Tree-sitter highlighting enabled")

print("TEST_PASSED: All tree-sitter tests passed")
vim.cmd("qall!")
