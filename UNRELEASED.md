<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Changed

- Lex Monochrome theme colors are now resolved at generate time, matching the strategy used by the vscode and zed editor packages. `scripts/gen-theme.py` emits `lua/lex/theme_data.lua` with per-mode `PALETTE` and `RULES` tables carrying absolute hex values pre-resolved from the canonical intensity/background tiers in `comms/shared/theming/lex-theme.json`. The `apply_monochrome` runtime path picks the table by `vim.o.background` and applies entries directly — no `colors[rule.intensity]` indirection. No visual change; same hex values, resolved once at generate time instead of at every apply. (#26, #27)
- Bumped `comms` submodule to v0.15.0 (canonical Lex monochrome theme + EDITORS.lex parity reference + `:: notes ::` annotation samples).
- Bumped `tree-sitter` pin from v0.9.1 to v0.10.1 in `shared/lex-deps.json`. Picks up the embedded-grammars manifest, the new quarterly grammar-bump workflow, and the comms catch-up. Vendored `queries/lex/*.scm` already match the v0.10.1 tarball — no query sync needed.
- Repo onboarded to the canonical lex-fmt CI standardization: `.github/CODEOWNERS` and `.github/workflows/copilot-review.yml` for auto-trigger Copilot review on PRs. (#25)
