<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Added

- Extension trust prompt. When `lexd-lsp` boots a workspace with a
  `[labels]` namespace whose subprocess handler hasn't been pinned in
  `<workspace>/.lex/trust.json`, the server fires a `lex/trustRequest`
  custom request and the plugin renders a synchronous
  `vim.fn.confirm` modal with **Trust** / **Deny** buttons (Deny is
  the default; Esc / cancel maps to Deny — fail-closed). The modal
  shows the namespace name, schema source (lex.toml `[labels]`
  entry, local schema directory, or cached fetch URI), command
  string, and declared capability set. The user's reply is fed
  back to the trust gate and pinned for subsequent sessions. Pairs
  with `lexd-lsp` v0.11+ which adds the trust-request forwarding
  (lex-fmt/lex#549). Part of the γ phase of the extension system
  (lex-fmt/lex#516).
- New integration test (`test/test_lsp_trust_prompt.lua`) covering:
  - the `trust_prompt.handle()` contract — Trust → trusted, Deny →
    denied with reason, cancelled (Esc / `confirm=0`) → also denied
    (fail-closed) — with `vim.fn.confirm` patched so the test
    captures the user-facing prompt body
  - `lex.setup()` wiring — with `lspconfig` / `lspconfig.configs`
    stubbed via `package.loaded`, asserts that the plugin
    registers `trust_prompt.handle` as the
    `lsp_config.handlers["lex/trustRequest"]` value, and that a
    user-supplied override is preserved (not clobbered).

### Changed

- Bumped `lexd-lsp` pin from v0.10.6 to v0.11.0. Picks up the
  extension dispatch + trust-prompt forwarding + boot-serialization
  wiring this plugin's trust-prompt handler depends on. See lex-fmt/lex
  CHANGELOG `[0.11.0]` for the full surface.
