-- Lex Theme Module
-- =================
-- Handles syntax highlighting for Lex documents.
--
-- Two themes available:
--   "monochrome" - Grayscale highlighting (default)
--   "native"     - Links to standard treesitter groups

local M = {}

-- Apply native theme: links to standard treesitter/markup groups
function M.apply_native()
  -- Content text - use standard markup groups
  vim.api.nvim_set_hl(0, "@lsp.type.SessionTitleText", { link = "@markup.heading", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.DefinitionSubject", { link = "@markup.heading", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.DefinitionContent", { link = "@markup", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.InlineStrong", { link = "@markup.strong", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.InlineEmphasis", { link = "@markup.italic", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.InlineCode", { link = "@markup.raw", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.InlineMath", { link = "@markup.math", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.VerbatimContent", { link = "@markup.raw.block", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.ListItemText", { link = "@markup", default = true })

  -- Structural elements - use punctuation/delimiter groups
  vim.api.nvim_set_hl(0, "@lsp.type.DocumentTitle", { bold = true, underline = true, default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.DocumentSubtitle", { italic = true, default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.SessionMarker", { link = "@punctuation.special", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.ListMarker", { link = "@markup.list", default = true })

  -- References - use link groups
  vim.api.nvim_set_hl(0, "@lsp.type.Reference", { link = "@markup.link", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.ReferenceCitation", { link = "@markup.link", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.ReferenceFootnote", { link = "@markup.link", default = true })

  -- Meta-information - use comment group
  vim.api.nvim_set_hl(0, "@lsp.type.AnnotationLabel", { link = "@comment", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.AnnotationParameter", { link = "@comment", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.AnnotationContent", { link = "@comment", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.VerbatimSubject", { link = "@label", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.VerbatimLanguage", { link = "@label", default = true })
  vim.api.nvim_set_hl(0, "@lsp.type.VerbatimAttribute", { link = "@attribute", default = true })

  -- Inline markers - use punctuation delimiter
  local marker_groups = {
    "InlineMarker_strong_start", "InlineMarker_strong_end",
    "InlineMarker_emphasis_start", "InlineMarker_emphasis_end",
    "InlineMarker_code_start", "InlineMarker_code_end",
    "InlineMarker_math_start", "InlineMarker_math_end",
    "InlineMarker_ref_start", "InlineMarker_ref_end",
  }
  for _, name in ipairs(marker_groups) do
    vim.api.nvim_set_hl(0, "@lsp.type." .. name, { link = "@punctuation.delimiter", default = true })
  end
end

-- Apply monochrome theme: grayscale highlighting that adapts to dark/light mode.
-- Palette + token rules come from lua/lex/theme-data.lua, which is generated
-- by scripts/gen-theme.py from comms/shared/theming/lex-theme.json.
function M.apply_monochrome()
  local theme_data = require("lex.theme-data")
  local mode = vim.o.background == "dark" and "dark" or "light"
  local colors = theme_data.COLORS[mode]

  -- Define base intensity groups (user-overridable)
  vim.api.nvim_set_hl(0, "@lex.normal", { fg = colors.normal, default = true })
  vim.api.nvim_set_hl(0, "@lex.muted", { fg = colors.muted, default = true })
  vim.api.nvim_set_hl(0, "@lex.faint", { fg = colors.faint, default = true })
  vim.api.nvim_set_hl(0, "@lex.faintest", { fg = colors.faintest, default = true })

  -- Apply each token rule. The data carries intensity + style flags +
  -- optional background; resolve them against the live palette here.
  for _, rule in ipairs(theme_data.TOKENS) do
    local hl = { fg = colors[rule.intensity] }
    if rule.bold then hl.bold = true end
    if rule.italic then hl.italic = true end
    if rule.underline then hl.underline = true end
    if rule.background then hl.bg = colors[rule.background] end
    vim.api.nvim_set_hl(0, "@lsp.type." .. rule.token, hl)
  end
end

-- Apply tree-sitter highlight groups scoped to lex filetype.
-- These provide base highlighting before LSP semantic tokens arrive.
-- Using @capture.lex suffix scopes these to lex buffers only.
function M.apply_treesitter_native()
  -- Tree-sitter captures from highlights.scm already use standard groups
  -- (@markup.heading, @markup.raw, etc.) which colorschemes handle natively.
  -- Only set lex-scoped groups where we need overrides.
  vim.api.nvim_set_hl(0, "@variable.other.definition.lex", { link = "@markup.heading", default = true })
  vim.api.nvim_set_hl(0, "@constant.builtin.lex", { link = "@markup.link", default = true })
  vim.api.nvim_set_hl(0, "@keyword.lex", { link = "@keyword", default = true })
end

function M.apply_treesitter_monochrome()
  local is_dark = vim.o.background == "dark"
  local colors = is_dark and {
    normal = "#e0e0e0",
    muted = "#888888",
    faint = "#666666",
    faintest = "#555555",
    code_bg = "#2a2a2a",
  } or {
    normal = "#000000",
    muted = "#808080",
    faint = "#b3b3b3",
    faintest = "#cacaca",
    code_bg = "#f5f5f5",
  }

  -- Session titles (headings) and document subtitle
  vim.api.nvim_set_hl(0, "@markup.heading.lex", { fg = colors.normal, bold = true })
  vim.api.nvim_set_hl(0, "@markup.heading.subtitle.lex", { fg = colors.normal, italic = true })
  vim.api.nvim_set_hl(0, "@punctuation.definition.heading.lex", { fg = colors.muted })

  -- Definitions
  vim.api.nvim_set_hl(0, "@variable.other.definition.lex", { fg = colors.normal, italic = true })

  -- Verbatim blocks
  vim.api.nvim_set_hl(0, "@markup.raw.block.lex", { fg = colors.faint })
  vim.api.nvim_set_hl(0, "@markup.raw.lex", { fg = colors.normal, bg = colors.code_bg })
  vim.api.nvim_set_hl(0, "@markup.raw.inline.lex", { fg = colors.normal })

  -- Lists
  vim.api.nvim_set_hl(0, "@markup.list.lex", { fg = colors.muted, italic = true })

  -- Annotations
  vim.api.nvim_set_hl(0, "@punctuation.special.lex", { fg = colors.faint })
  vim.api.nvim_set_hl(0, "@comment.lex", { fg = colors.faint })

  -- Inline formatting
  vim.api.nvim_set_hl(0, "@markup.bold.lex", { fg = colors.normal, bold = true })
  vim.api.nvim_set_hl(0, "@markup.italic.lex", { fg = colors.normal, italic = true })
  vim.api.nvim_set_hl(0, "@markup.math.lex", { fg = colors.normal, italic = true })
  vim.api.nvim_set_hl(0, "@string.escape.lex", { fg = colors.faint })

  -- References
  vim.api.nvim_set_hl(0, "@markup.link.lex", { fg = colors.muted, underline = true })
  vim.api.nvim_set_hl(0, "@markup.link.url.lex", { fg = colors.muted, underline = true })
  vim.api.nvim_set_hl(0, "@constant.builtin.lex", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "@keyword.lex", { fg = colors.faint })
end

--- Apply tree-sitter theme (called after tree-sitter setup succeeds)
--- @param theme_name string "monochrome" or "native"
function M.apply_treesitter(theme_name)
  if theme_name == "native" then
    M.apply_treesitter_native()
  else
    M.apply_treesitter_monochrome()
  end
end

-- Apply the specified theme
-- @param theme_name string: "monochrome" (default) or "native"
function M.apply(theme_name)
  if theme_name == "native" then
    M.apply_native()
  else
    M.apply_monochrome()
  end
end

return M
