<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Changed

- Bumped `lexd-lsp` pin from v0.10.5 to v0.10.6. Picks up the LSP
  position UTF-16 column fix: inline tokens and goto-definition /
  find-references targets now land on the correct character even when
  the line contains non-ASCII characters like `→`. Previously the LSP
  was sending UTF-8 byte offsets where UTF-16 code-unit offsets were
  expected, so any line with such a character had downstream tokens
  shifted right by `len_utf8 - len_utf16` per occurrence.
- Bumped `comms` submodule pin to v0.16.1 and regenerated
  `lua/lex/theme_data.lua`. In the **monochrome theme** (the default,
  `setup({ theme = "mono" })`), reference inlines now render with
  **bold** instead of underline. Underline reads as "follow this link"
  and conflicted with the LSP `documentLink` decoration; bold matches
  the way references read in printed text. The **native theme** path
  (`setup({ theme = "native" })`) is unchanged — it links references
  to `@markup.link` so references inherit whatever style the user's
  colorscheme assigns to that group, which is the design intent of the
  native mode.
