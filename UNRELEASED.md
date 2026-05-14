<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Changed

- Bumps `lexd-lsp` pin v0.12.0 → v0.13.0
  ([lex v0.13.0 release](https://github.com/lex-fmt/lex/releases/tag/v0.13.0)).
  This brings in the bare-as-blessed label namespace model
  ([lex#584](https://github.com/lex-fmt/lex/issues/584)) and the
  wire-v2 reverse-hook surface
  ([lex#583](https://github.com/lex-fmt/lex/issues/583)). User-facing
  changes flow through standard LSP responses:
    - **Label-policy diagnostics.** `:: doc.foo ::` (reserved-forbidden)
      and `:: lex.unknown ::` (unregistered canonical) now surface via
      `vim.diagnostic` with codes `forbidden-label-prefix` /
      `unknown-lex-canonical`.
    - **Quickfix code action.** Code actions
      (`vim.lsp.buf.code_action()`) on a `doc.*` site offer "Rewrite
      `doc.table` to `table`" / `doc.image` → `image` etc. for the
      four curated mappings, plus a generic "strip `doc.` prefix"
      fallback.
    - **Hover form-classification.** Hovering a label site shows
      "Shortcut for `lex.metadata.author`" / "Prefix-stripped form of
      `lex.metadata.author`" / "Community label" depending on the
      source spelling.
    - **Permissive parse for diagnostics.** A `:: doc.foo ::` in a
      file no longer blanks out the rest of the LSP surface — the
      offending label gets a diagnostic in place and other features
      keep working.
- Bumps `comms` submodule to `2238b40`. **Required** for the lex v0.13.0
  bump: comms#43 flipped benchmark fixtures off `doc.note` →
  `test.note`, and nvim's LSP tests load those fixtures via
  `test/test_lsp_*.lua`. Without the bump, strict `NormalizeLabels` in
  v0.13.0 rejects the fixtures at parse time.
