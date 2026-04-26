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

-- Test 3: Run injection query and check for matches.
-- Pair each (language, content) capture inside a single match so we can
-- assert that the language name lines up with a real, non-empty content
-- range — this is what nvim-treesitter consumes to actually inject.
local last_buf_line = vim.api.nvim_buf_line_count(0) - 1
local zones = {} -- list of { lang = string, sr, sc, er, ec }
local langs_seen = {}

for _, match, _ in injection_query:iter_matches(root, 0) do
  local lang_text, content_node
  for id, nodes in pairs(match) do
    local cap_name = injection_query.captures[id]
    local node = type(nodes) == "table" and nodes[1] or nodes
    if cap_name == "injection.language" then
      lang_text = vim.treesitter.get_node_text(node, 0)
    elseif cap_name == "injection.content" then
      content_node = node
    end
  end
  if lang_text and content_node then
    local lang = lang_text:match("^%s*(%S+)")
    if lang and lang ~= "table" then
      local sr, sc, er, ec = content_node:range()
      table.insert(zones, { lang = lang, sr = sr, sc = sc, er = er, ec = ec })
      langs_seen[lang] = (langs_seen[lang] or 0) + 1
    end
  end
end

-- Every language in the fixture should appear at least once.
for _, expected in ipairs({ "python", "javascript", "json", "rust", "bash" }) do
  if not langs_seen[expected] then
    print("TEST_FAILED: No " .. expected .. " injection detected")
    vim.cmd("cquit 1")
  end
end

print(string.format("TEST_PASSED: Injection zones detected for %d languages (%d total zones)",
  vim.tbl_count(langs_seen), #zones))

-- Every zone must have a non-empty content range that lies inside the buffer.
for _, z in ipairs(zones) do
  if z.sr > z.er or (z.sr == z.er and z.sc >= z.ec) then
    print(string.format("TEST_FAILED: Empty/invalid range for %s: %d:%d -> %d:%d",
      z.lang, z.sr, z.sc, z.er, z.ec))
    vim.cmd("cquit 1")
  end
  if z.er > last_buf_line + 1 then
    print(string.format("TEST_FAILED: Range for %s extends past buffer (%d > %d)",
      z.lang, z.er, last_buf_line + 1))
    vim.cmd("cquit 1")
  end
end

print("TEST_PASSED: All injection.content ranges are well-formed and inside the buffer")

-- The "plain verbatim" block (no annotation) must NOT produce an injection.
-- Walk the tree and find a verbatim_block whose annotation_header text is
-- empty/missing; assert no zone overlaps its content range.
local function find_plain_verbatim(node)
  if node:type() == "verbatim_block" then
    local has_lang_annotation = false
    for child in node:iter_children() do
      if child:type() == "annotation_header" then
        local text = vim.treesitter.get_node_text(child, 0) or ""
        if text:match("%S") then
          has_lang_annotation = true
        end
      end
    end
    if not has_lang_annotation then
      return node
    end
  end
  for child in node:iter_children() do
    local found = find_plain_verbatim(child)
    if found then return found end
  end
  return nil
end

local plain = find_plain_verbatim(root)
if plain then
  local psr, _, per, _ = plain:range()
  for _, z in ipairs(zones) do
    if z.sr >= psr and z.er <= per then
      print(string.format("TEST_FAILED: Plain verbatim block (%d-%d) wrongly produced %s injection",
        psr, per, z.lang))
      vim.cmd("cquit 1")
    end
  end
  print("TEST_PASSED: Plain verbatim block correctly produced no injection")
else
  print("TEST_PASSED: (no plain verbatim block in fixture; skipped negative check)")
end

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
