<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Changed

- Diagnostics published by `lexd-lsp` now render visibly in the buffer by default — `virtual_text`, `signs`, `underline`, and `severity_sort` are turned on inside `on_attach`. Previously the diagnostics arrived (visible to `:lua print(vim.inspect(vim.diagnostic.get(0)))`) but rendered nothing on screen unless the user had configured `vim.diagnostic.config(...)` themselves. The config is namespace-scoped to `lexd-lsp` so it does not affect other language servers attached to the same nvim. Highlight groups, sign characters, and message formatting are deliberately left to the user's colorscheme — Lex-themed diagnostics (monochrome intensity tiers, custom sign chars) are a separate opt-in design.
