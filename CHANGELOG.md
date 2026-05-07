# Changelog

## v0.8.4 (2026-05-07)

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

## v0.8.3 (2026-05-07)

### Changed

- Bumped `lexd-lsp` pin from v0.10.2 to v0.10.5. Two LSP-side fixes for the
  document-link surface (`textDocument/documentLink`): link ranges are now
  scoped to the `[bracketed]` reference instead of the containing
  paragraph or title line, and references in section headings (e.g.
  `1. See [./handlers.lex] for details`) now also produce links — the LSP
  was previously dropping them silently.

## v0.8.2 (2026-05-05)

### Changed

- Bumped `lexd-lsp` pin from v0.10.1 to v0.10.2. Picks up the include-resolver security hardening: `FsLoader` now defends against arbitrary-file-read via symlink path traversal (canonicalizes both the requested path and the resolution root, then verifies the canonical target sits under the canonical root); rejects non-regular files (FIFOs, sockets, devices) before reading; enforces a configurable per-file size cap (default 10 MiB) and total-includes cap (default 1000); rejects platform-absolute include `src` (`C:\foo`, `\\server\share`) up front. Three new diagnostic codes are surfaced: `include-total-exceeded`, `include-file-too-large`, `include-absolute-path`. (lex-fmt/lex#502, #503, #504)

## v0.8.1 (2026-05-04)

### Changed

- Diagnostics published by `lexd-lsp` now render visibly in the buffer by default — `virtual_text`, `signs`, `underline`, and `severity_sort` are turned on inside `on_attach`. Previously the diagnostics arrived (visible to `:lua print(vim.inspect(vim.diagnostic.get(0)))`) but rendered nothing on screen unless the user had configured `vim.diagnostic.config(...)` themselves. The config is namespace-scoped to `lexd-lsp` so it does not affect other language servers attached to the same nvim. Highlight groups, sign characters, and message formatting are deliberately left to the user's colorscheme — Lex-themed diagnostics (monochrome intensity tiers, custom sign chars) are a separate opt-in design. (#30)
- Bumped `lexd-lsp` pin from v0.10.0 to v0.10.1. Picks up the fix that points the `include-not-found` diagnostic at the offending `:: lex.include src=… ::` annotation instead of the document head — the squiggle now lands where the user expects it, particularly important in docs with multiple includes. (lex-fmt/lex#500)

## v0.8.0 (2026-05-04)

### Changed

- Bumped `lexd-lsp` pin from v0.8.8 to v0.10.0. Adds the `lex.include` annotation surface in the editor: real-time include diagnostics (broken paths, cycles, depth-exceeded, root-escape, container-policy violations, etc.) on every edit, goto-definition that jumps from `:: lex.include src="chapter.lex" ::` into the target file, and a hover preview that shows the resolved path plus the first non-blank lines of the target. No editor-side configuration required — the LSP handles include resolution from the host's `[includes]` config (with sensible defaults).
- Bumped `comms` submodule to v0.16.0 (canonical `lex.include` element doc + fixture set + formal reservation of the `lex.*` annotation namespace).

### Fixed

- CI: handle the new arthur-debert/release@v1 tarball layout (lex v0.10.0+ packages binaries under `<name>-<target>/` instead of at the top level). Locate the binary by name post-extract so this works for both layouts. (#29)

## v0.7.10 (2026-05-02)

### Changed

- Lex Monochrome theme colors are now resolved at generate time, matching the strategy used by the vscode and zed editor packages. `scripts/gen-theme.py` emits `lua/lex/theme_data.lua` with per-mode `PALETTE` and `RULES` tables carrying absolute hex values pre-resolved from the canonical intensity/background tiers in `comms/shared/theming/lex-theme.json`. The `apply_monochrome` runtime path picks the table by `vim.o.background` and applies entries directly — no `colors[rule.intensity]` indirection. No visual change; same hex values, resolved once at generate time instead of at every apply. (#26, #27)
- Bumped `comms` submodule to v0.15.0 (canonical Lex monochrome theme + EDITORS.lex parity reference + `:: notes ::` annotation samples).
- Bumped `tree-sitter` pin from v0.9.1 to v0.10.1 in `shared/lex-deps.json`. Picks up the embedded-grammars manifest, the new quarterly grammar-bump workflow, and the comms catch-up. Vendored `queries/lex/*.scm` already match the v0.10.1 tarball — no query sync needed.
- Repo onboarded to the canonical lex-fmt CI standardization: `.github/CODEOWNERS` and `.github/workflows/copilot-review.yml` for auto-trigger Copilot review on PRs. (#25)

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
