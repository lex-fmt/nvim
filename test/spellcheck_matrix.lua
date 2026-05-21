-- Headless e2e test: spell capture matrix for the spellcheck fixture.
--
-- Verifies the effective @spell / @nospell tree-sitter state at known prose
-- positions in `tree-sitter-lex/test/spellcheck-fixture.lex`. Resolves
-- "effective spell" as: @nospell wins over @spell when both apply.
--
-- Run from this plugin's root:
--
--   LEX_TREESITTER_PATH=/path/to/tree-sitter-lex \
--     nvim --clean --headless -u NONE -i NONE -l test/spellcheck_matrix.lua
--
-- The --clean flag is load-bearing: nvim's tree-sitter runtime merges every
-- queries/lex/*.scm on the runtimepath (including any user override under
-- ~/.config/nvim/queries/lex/ with `;extends`), so an isolated runtime is
-- required to test the plugin's queries in isolation.
--
-- Exits 0 on full pass, 1 on any mismatch (prints a diff).

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local ts_path = os.getenv("LEX_TREESITTER_PATH")
if not ts_path or ts_path == "" then
  ts_path = vim.fn.fnamemodify(plugin_root .. "/../tree-sitter-lex", ":p"):gsub("/$", "")
end

local fixture = ts_path .. "/test/spellcheck-fixture.lex"

if vim.fn.filereadable(fixture) == 0 then
  io.stderr:write("fixture not found: " .. fixture .. "\n")
  os.exit(2)
end

-- Isolate runtimepath so the user's ~/.config/nvim/queries/lex/*.scm (which
-- typically uses `;extends` to add their own captures) doesn't merge with the
-- queries under test. Test must reflect ONLY the plugin's queries.
local nvim_share = vim.env.VIMRUNTIME
vim.opt.runtimepath = { plugin_root, nvim_share }
vim.opt.packpath = ""
package.path = plugin_root .. "/lua/?.lua;" .. plugin_root .. "/lua/?/init.lua;" .. package.path

-- Compile + register the lex parser from the local tree-sitter-lex checkout.
local ts_setup = require("lex.treesitter")
local ok = ts_setup.setup({ path = ts_path })
if not ok then
  io.stderr:write("lex.treesitter.setup failed (path=" .. ts_path .. ")\n")
  os.exit(2)
end

-- Wire up the .lex filetype and load the buffer.
vim.filetype.add({ extension = { lex = "lex" } })
vim.cmd("edit " .. vim.fn.fnameescape(fixture))
local bufnr = vim.api.nvim_get_current_buf()
vim.bo[bufnr].filetype = "lex"

-- Start the tree-sitter highlighter so queries (and predicates) run.
local started, start_err = pcall(vim.treesitter.start, bufnr, "lex")
if not started then
  io.stderr:write("vim.treesitter.start failed: " .. tostring(start_err) .. "\n")
  os.exit(2)
end

-- Force a parse so captures resolve.
vim.treesitter.get_parser(bufnr, "lex"):parse()

-- Helpers -------------------------------------------------------------------

local function find_word(needle)
  for i = 0, vim.api.nvim_buf_line_count(bufnr) - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
    local start = line:find(needle, 1, true)
    if start then
      return i, start - 1, line
    end
  end
  return nil
end

-- Effective spell at byte (row, col):
--   @nospell wins over @spell when both fire.
--   Inspects only the lex language; injected sublanguages are ignored.
local function effective_spell_at(row, col)
  local caps = vim.treesitter.get_captures_at_pos(bufnr, row, col)
  local saw_spell, saw_nospell = false, false
  for _, c in ipairs(caps) do
    if c.lang == "lex" then
      if c.capture == "spell" then saw_spell = true end
      if c.capture == "nospell" then saw_nospell = true end
    end
  end
  if saw_nospell then return "nospell" end
  if saw_spell then return "spell" end
  return "none"
end

local function check(needle, expected)
  local row, col, line = find_word(needle)
  if not row then
    return { ok = false, msg = string.format("needle %q not found in fixture", needle) }
  end
  -- Probe a column in the middle of the needle.
  local probe_col = col + math.floor(#needle / 2)
  local actual = effective_spell_at(row, probe_col)
  return {
    ok = actual == expected,
    msg = string.format(
      "%-40s @ (%d,%d) expected=%s actual=%s  line: %s",
      "'" .. needle .. "'",
      row,
      probe_col,
      expected,
      actual,
      (line or ""):sub(1, 70)
    ),
  }
end

-- Matrix --------------------------------------------------------------------
--
-- Each entry: { needle (plain-text substring), expected ("spell" | "nospell") }
-- The needle is searched in the buffer; the probe column lands inside it.

local matrix = {
  -- Prose positions: should be spell-checked
  { "Spelchek Fixture",                  "spell" },
  { "contians a recieve",                "spell" },
  { "Sectoin: Prose",                    "spell" },
  { "A paragraph that occured",          "spell" },
  { "A list item with the Mispelled",    "spell" },
  { "Mispelled term:",                   "spell" },
  { "definition body that contians",     "spell" },
  { "Brokn table caption:",              "spell" },
  { " Coloumn A ",                       "spell" },
  { "cell with occured",                 "spell" },
  { "Sectoin: Verbatim",                 "spell" },
  -- Verbatim subject: prose per policy
  { "Pythn code example:",               "spell" },
  -- Annotation trailing descriptor: prose
  { "trailing descriptor with teh typo", "spell" },
  -- Annotation block body: prose
  { "body of this annotation contians",  "spell" },
  { "should be spell-checked like any",  "spell" },

  -- Verbatim body lines: code/preformatted
  { "def teh_function",                  "nospell" },
  { "this comment has occured but",      "nospell" },
  { "return recieve",                    "nospell" },

  -- Annotation labels + params: not prose
  { "note nott_a_typo_label",            "nospell" },
  { "data src=somepath",                 "nospell" },

  -- Code span + math span + reference inside otherwise-prose paragraph
  { "teh code span",                     "nospell" },
  { "teh math",                          "nospell" },
  { "teh refernce",                      "nospell" },
}

-- Run ----------------------------------------------------------------------

local fails = {}
for _, t in ipairs(matrix) do
  local r = check(t[1], t[2])
  if r.ok then
    print("PASS  " .. r.msg)
  else
    print("FAIL  " .. r.msg)
    table.insert(fails, r.msg)
  end
end

print(string.format("\n%d / %d passed", #matrix - #fails, #matrix))
if #fails > 0 then
  os.exit(1)
end
os.exit(0)
