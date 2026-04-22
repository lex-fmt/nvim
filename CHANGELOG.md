# Changelog

## v0.7.6 (2026-04-22)

### Changed

- Bumped pinned LSP version to v0.8.5. Picks up two `lex-analysis` diagnostic fixes from lexd-lsp:
  - `missing-footnote` no longer false-positives on numbered references in a table cell when the resolving list is the table's own positional footnote list (lex-fmt/lex#460).
  - `table-inconsistent-columns` correctly accounts for `^^` rowspan carry-over when computing effective row width (lex-fmt/lex#458).

## Unreleased

### Changed

- Renamed LSP binary references from `lex-lsp` to `lexd-lsp` (companion to lex-fmt/lex#450)
- Bumped pinned LSP version to v0.8.5 (picks up the table-scoped footnote resolver fix from lex-fmt/lex#460 and the rowspan diagnostic fix from lex-fmt/lex#458)

### Fixed

- Replaced deprecated `vim.lsp.semantic_tokens.start` with `vim.lsp.semantic_tokens.enable` (removed in Nvim 0.13)
