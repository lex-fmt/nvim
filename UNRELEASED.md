<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Changed

- Bumped `lexd-lsp` pin from v0.10.2 to v0.10.5. Two LSP-side fixes for the
  document-link surface (`textDocument/documentLink`): link ranges are now
  scoped to the `[bracketed]` reference instead of the containing
  paragraph or title line, and references in section headings (e.g.
  `1. See [./handlers.lex] for details`) now also produce links — the LSP
  was previously dropping them silently.
