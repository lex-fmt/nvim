# Changelog

## Unreleased

### Changed

- Lex Monochrome theme colors are now resolved at generate time, matching the strategy used by the vscode and zed editor packages. `scripts/gen-theme.py` emits `lua/lex/theme_data.lua` with per-mode `PALETTE` and `RULES` tables carrying absolute hex values pre-resolved from the canonical intensity/background tiers in `comms/shared/theming/lex-theme.json`. The `apply_monochrome` runtime path picks the table by `vim.o.background` and applies entries directly — no `colors[rule.intensity]` indirection. No visual change; same hex values, resolved once at generate time instead of at every apply.

## v0.7.9 (2026-04-26)

- Strengthened the tree-sitter injection test to assert all five fixture
  languages (python, javascript, json, rust, bash), validate that
  `@injection.content` ranges are non-empty and inside the buffer, and
  reject any injection produced for plain (un-annotated) verbatim blocks.
- Fixed a stale `M.version` constant that had drifted from the released
  tag, and taught `scripts/create-release` to bump it automatically.

## v0.7.8 (2026-04-25)

### Changed

- Bumped pinned LSP version to v0.8.8. Picks up the "Add missing footnote definition" quickfix (lex-fmt/lex#463): when a footnote reference like `[1]` has no matching definition, the LSP now offers a code action that inserts the definition into an existing or new `:: notes ::` block. Available via `vim.lsp.buf.code_action()` — no plugin code change required.

### Fixed

- `queries/lex/highlights.scm`: synced to match tree-sitter v0.9.1 grammar. The vendored query still referenced the old `footnote_reference` node, which v0.9.0 of tree-sitter-lex renamed to `annotation_reference` (alongside the new `[::label]` syntax). `vim.treesitter.start` errored with `Invalid node type "footnote_reference"` whenever tree-sitter highlighting was enabled. Bug was latent on `main` since v0.7.7, surfaced (not introduced) by the v0.8.8 bump.

## v0.7.7 (2026-04-24)

### Changed

- Bumped pinned LSP version to v0.8.7 (picks up the comms v0.14.0 spec content).
- Bumped pinned tree-sitter grammar to v0.9.1 (picks up the new `[::label]` annotation reference syntax and directly-nested inline formatting markers).

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
