# Lex for Neovim

Neovim plugin for [Lex](https://github.com/lex-fmt/lex) — a plain text format for structured documents.

**[lex.ing](https://lex.ing)** — project site, specs, and documentation.

## Install

### lazy.nvim

```lua
{
    "lex-fmt/nvim",
    ft = "lex",
    dependencies = { "neovim/nvim-lspconfig" },
    config = function()
        require("lex").setup()
    end,
}
```

### packer.nvim

```lua
use {
    "lex-fmt/nvim",
    requires = { "neovim/nvim-lspconfig" },
    config = function()
        require("lex").setup()
    end,
}
```

The plugin auto-downloads the `lexd-lsp` binary on first use.

## Configuration

```lua
require("lex").setup({
    -- "monochrome" (default) or "native"
    theme = "monochrome",

    -- Override the lexd-lsp binary path
    cmd = { "/path/to/lexd-lsp" },

    -- Additional lspconfig options
    lsp_config = {
        on_attach = function(client, bufnr)
            -- your custom on_attach
        end,
    },
})
```

## Theme

Lex uses a monochrome theme by default — typography and grayscale intensity instead of colors. This keeps focus on content rather than syntax. The theme adapts to light and dark backgrounds.

Set `theme = "native"` to use your colorscheme instead, with standard `@markup.*` highlight groups.

You can override individual highlights after setup:

```lua
vim.api.nvim_set_hl(0, "@lsp.type.Reference", { fg = "#5588ff", underline = true })
vim.api.nvim_set_hl(0, "@lex.muted", { fg = "#666666" })
```

See `README.lex` for the full list of highlight groups.

## Commands

| Command | Description |
|---------|-------------|
| `:LexExportMarkdown [path]` | Export to Markdown |
| `:LexExportHtml [path]` | Export to HTML |
| `:LexExportPdf [path]` | Export to PDF |
| `:LexConvertToLex` | Convert current buffer (Markdown) to Lex |
| `:LexInsertAsset` | Insert asset reference at cursor |
| `:LexInsertVerbatim` | Insert verbatim block from file |
| `:LexResolveAnnotation` | Resolve annotation at cursor |
| `:LexToggleAnnotations` | Toggle all annotations resolved/unresolved |
| `:LexNextAnnotation` | Jump to next annotation (`]a`) |
| `:LexPrevAnnotation` | Jump to previous annotation (`[a`) |
| `:LexDebugToken` | Show semantic token under cursor |

## License

MIT
