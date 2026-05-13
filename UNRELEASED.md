<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Added

- **`:LexExtractToInclude`**
  ([lex#498](https://github.com/lex-fmt/lex/issues/498)). New
  range-capable user command that splits the visual selection out
  into a new include file referenced via
  `:: lex.include src="…" ::`. Invoke from visual mode
  (`:'<,'>LexExtractToInclude`); a `vim.ui.input` prompt asks for the
  target include path (relative to the includes root), and the LSP
  server in
  [lex v0.12.0](https://github.com/lex-fmt/lex/releases/tag/v0.12.0)
  validates + builds the WorkspaceEdit. Server `invalid_params`
  errors (URL scheme, root escape, existing target, missing parent
  dir, parse failures) surface via `vim.notify(level=ERROR)` carrying
  the typed `ExtractError` message verbatim.

### Changed

- Bumps `lexd-lsp` pin v0.11.0 → v0.12.0.
- `vim.lsp.util.apply_workspace_edit` silently no-ops the
  `TextDocumentEdit` targeted at a freshly-`CreateFile`'d URI (same
  gotcha vscode's `applyEdit` has). The extract wrapper walks the
  WorkspaceEdit by hand: writes each `CreateFile` target's content
  via `vim.fn.writefile`, then hands the remaining host edits to the
  standard `apply_workspace_edit` path.

### Fixed

- `LexExtractToInclude` now uses `opts.range > 0` as the gate so a
  normal-mode invocation can't accidentally operate on stale
  `'<`/`'>` marks left from a prior visual selection.
- Linewise visual (`V`) selections set `'>` column to
  `v:maxcol = 2147483647`; the old `+1` step overflowed and the
  server rejected the range. Now clamps the end column to the
  actual byte length of the end line.
