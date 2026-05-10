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
