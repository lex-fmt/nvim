# Changelog

## Unreleased

### Changed

- Renamed LSP binary references from `lex-lsp` to `lexd-lsp` (companion to lex-fmt/lex#450)
- Bumped pinned LSP version to v0.8.5 (picks up the table-scoped footnote resolver fix from lex-fmt/lex#460 and the rowspan diagnostic fix from lex-fmt/lex#458)

### Fixed

- Replaced deprecated `vim.lsp.semantic_tokens.start` with `vim.lsp.semantic_tokens.enable` (removed in Nvim 0.13)
