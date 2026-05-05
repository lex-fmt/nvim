<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

### Changed

- Bumped `lexd-lsp` pin from v0.10.1 to v0.10.2. Picks up the include-resolver security hardening: `FsLoader` now defends against arbitrary-file-read via symlink path traversal (canonicalizes both the requested path and the resolution root, then verifies the canonical target sits under the canonical root); rejects non-regular files (FIFOs, sockets, devices) before reading; enforces a configurable per-file size cap (default 10 MiB) and total-includes cap (default 1000); rejects platform-absolute include `src` (`C:\foo`, `\\server\share`) up front. Three new diagnostic codes are surfaced: `include-total-exceeded`, `include-file-too-large`, `include-absolute-path`. (lex-fmt/lex#502, #503, #504)
