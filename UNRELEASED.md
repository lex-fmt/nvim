<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Changed

- Bumped pinned LSP version to v0.8.8. Picks up the "Add missing footnote definition" quickfix (lex-fmt/lex#463): when a footnote reference like `[1]` has no matching definition, the LSP now offers a code action that inserts the definition into an existing or new `:: notes ::` block. Available via `vim.lsp.buf.code_action()` — no plugin code change required.

### Fixed

- `queries/lex/highlights.scm`: synced to match tree-sitter v0.9.1 grammar. The vendored query still referenced the old `footnote_reference` node, which v0.9.0 of tree-sitter-lex renamed to `annotation_reference` (alongside the new `[::label]` syntax). `vim.treesitter.start` errored with `Invalid node type "footnote_reference"` whenever tree-sitter highlighting was enabled. Bug was latent on `main` since v0.7.7, surfaced (not introduced) by the v0.8.8 bump.
