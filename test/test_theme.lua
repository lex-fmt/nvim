-- Headless unit test for lua/lex/theme.lua.
--
-- theme.lua is pure: it only calls nvim_set_hl to register highlight
-- groups, with no LSP, tree-sitter, or network dependency. So we run it
-- under `nvim --headless -u NONE -l this_file.lua` (no plugin runtime
-- needed) and inspect the resulting groups via nvim_get_hl.
--
-- Covered:
--   * apply("native")      -> link-based groups (DefinitionContent links to @markup)
--   * apply("monochrome")  -> palette-resolved fg per background mode (dark vs light)
--   * monochrome rule attrs (bold/italic/underline/bg) survive the apply loop
--   * apply() / apply_treesitter() dispatch on the theme_name argument
-- Prints TEST_PASSED / TEST_FAILED markers for the TAP runner.

local script_path = debug.getinfo(1, "S").source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

local function fail(msg)
  print("TEST_FAILED: " .. msg)
  vim.cmd("cquit 1")
end

local function assert_eq(got, want, what)
  if got ~= want then
    fail(string.format("%s: expected %s, got %s", what, vim.inspect(want), vim.inspect(got)))
  end
end

local theme = require("lex.theme")
local theme_data = require("lex.theme_data")

-- Defensive: a fresh require should not have mutated theme_data.
assert(type(theme.apply) == "function", "theme.apply must be a function")

-- ---------------------------------------------------------------------------
-- 1. native theme: groups are registered as links to standard markup groups.
-- ---------------------------------------------------------------------------
theme.apply("native")

-- DefinitionContent links to @markup; nvim_get_hl with link=false would
-- follow it, so ask for the raw definition to see the link target.
local def_content = vim.api.nvim_get_hl(0, { name = "@lsp.type.DefinitionContent", link = true })
assert_eq(def_content.link, "@markup", "native: DefinitionContent link target")

local strong = vim.api.nvim_get_hl(0, { name = "@lsp.type.InlineStrong", link = true })
assert_eq(strong.link, "@markup.strong", "native: InlineStrong link target")

-- A looped inline-marker group must also be linked.
local marker = vim.api.nvim_get_hl(0, { name = "@lsp.type.InlineMarker_code_start", link = true })
assert_eq(marker.link, "@punctuation.delimiter", "native: InlineMarker link target")

-- ---------------------------------------------------------------------------
-- 2. monochrome theme resolves the per-mode palette into the base groups.
-- ---------------------------------------------------------------------------
local function hex(n)
  -- nvim_get_hl returns fg/bg as a 24-bit integer; compare against the
  -- "#rrggbb" strings the theme uses.
  if n == nil then
    return nil
  end
  return string.format("#%06x", n)
end

-- Sanity: the dark/light normal colors must differ, else mode-switch
-- assertions below would be vacuous.
if theme_data.PALETTE.dark.normal == theme_data.PALETTE.light.normal then
  fail("fixture sanity: dark and light normal palette must differ for this test to be meaningful")
end

-- The base @lex.* intensity groups are registered with `default = true`
-- (user-overridable), so on a *fresh* apply they resolve to the current
-- background's palette. Test that against dark since this is the first
-- monochrome apply in the run.
vim.o.background = "dark"
theme.apply("monochrome")
local lex_normal = vim.api.nvim_get_hl(0, { name = "@lex.normal" })
assert_eq(hex(lex_normal.fg), theme_data.PALETTE.dark.normal, "monochrome/dark: @lex.normal fg")
local lex_muted = vim.api.nvim_get_hl(0, { name = "@lex.muted" })
assert_eq(hex(lex_muted.fg), theme_data.PALETTE.dark.muted, "monochrome/dark: @lex.muted fg")

-- ---------------------------------------------------------------------------
-- 3. monochrome RULES apply fg + attrs (bold/italic/underline/bg) faithfully,
--    and DO re-resolve per background mode (unlike the default=true base groups).
-- ---------------------------------------------------------------------------
local function find_rule(mode, token)
  for _, r in ipairs(theme_data.RULES[mode]) do
    if r.token == token then
      return r
    end
  end
  return nil
end

-- After the dark apply above, a RULES-driven group must carry the dark fg.
local dark_dt = find_rule("dark", "DocumentTitle")
assert(dark_dt, "fixture: DocumentTitle rule must exist in dark mode")
local got_dark_title = vim.api.nvim_get_hl(0, { name = "@lsp.type.DocumentTitle" })
assert_eq(hex(got_dark_title.fg), dark_dt.fg, "monochrome/dark: DocumentTitle fg")

-- Re-apply in light: the RULES group re-resolves (no default=true), proving
-- a real mode switch on the @lsp.type.* groups.
vim.o.background = "light"
theme.apply("monochrome")

local light_dt = find_rule("light", "DocumentTitle")
assert(light_dt, "fixture: DocumentTitle rule must exist in light mode")
local got_light_title = vim.api.nvim_get_hl(0, { name = "@lsp.type.DocumentTitle" })
assert_eq(hex(got_light_title.fg), light_dt.fg, "monochrome/light: DocumentTitle fg re-resolved")
assert_eq(got_light_title.bold or false, light_dt.bold or false, "monochrome: DocumentTitle bold")
assert_eq(got_light_title.underline or false, light_dt.underline or false, "monochrome: DocumentTitle underline")

-- A rule carrying bg must propagate bg too (VerbatimContent has a code bg).
local verbatim = find_rule("light", "VerbatimContent")
if verbatim and verbatim.bg then
  local got_verb = vim.api.nvim_get_hl(0, { name = "@lsp.type.VerbatimContent" })
  assert_eq(hex(got_verb.bg), verbatim.bg, "monochrome: VerbatimContent bg")
end

-- ---------------------------------------------------------------------------
-- 4. dispatch: apply()/apply_treesitter() default to monochrome, route "native".
-- ---------------------------------------------------------------------------
-- apply_treesitter("native") sets the lex-scoped keyword link; the
-- monochrome path sets it as a concrete fg instead. Use that to tell them apart.
theme.apply_treesitter("native")
local kw_native = vim.api.nvim_get_hl(0, { name = "@keyword.lex", link = true })
assert_eq(kw_native.link, "@keyword", "apply_treesitter(native): @keyword.lex links to @keyword")

theme.apply_treesitter("monochrome")
local kw_mono = vim.api.nvim_get_hl(0, { name = "@keyword.lex", link = true })
if kw_mono.link ~= nil then
  fail("apply_treesitter(monochrome): @keyword.lex should be a concrete group, not a link")
end
if kw_mono.fg == nil then
  fail("apply_treesitter(monochrome): @keyword.lex should have a resolved fg")
end

-- Unknown / nil theme name falls through to the monochrome branch (the else).
theme.apply_treesitter(nil)
local kw_default = vim.api.nvim_get_hl(0, { name = "@keyword.lex", link = true })
if kw_default.link ~= nil then
  fail("apply_treesitter(nil): default branch should be monochrome (concrete), not a link")
end

print("TEST_PASSED: theme module native/monochrome apply + dispatch")
vim.cmd("qall!")
