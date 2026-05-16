#!/usr/bin/env bash
# scripts/setup-dev-env.sh — per-session dev-environment setup, invoked by
# the SessionStart hook in .claude/settings.json.
#
# Cloud-only: local sessions exit early (devs already have their env set up).
# Detects stack by filesystem signals — works for rust, node-flavored
# (npm/yarn/pnpm), ruby (bundle), and nvim/zed/static-site (no project
# deps, just lefthook wiring). Stack-specific extras (e.g. resource
# download scripts, submodule init) can be added below the universal
# section as needed for the particular repo.
#
# Idempotent — safe to re-run. Errors are best-effort: a failure in one
# step doesn't abort the rest (e.g. transient registry hiccup on cargo
# fetch shouldn't block the lefthook install).

set -euo pipefail

# Cloud-only gate. Local sessions already have their env set up.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

# 1. Project dep cache — pick the right tool based on lockfile / manifest.

# Rust: cargo fetch with --locked so we don't silently mutate Cargo.lock
# in the per-session clone. Stale lockfile produces a non-fatal exit;
# the agent's later cargo build/test surfaces the real issue.
if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  cargo fetch --locked --quiet || true
fi

# Node-based (npm / yarn / pnpm). Skip if node_modules already exists
# (warm from a previous session within the same env-snapshot).
if [ -f package.json ] && [ ! -d node_modules ]; then
  if [ -f package-lock.json ] && command -v npm >/dev/null 2>&1; then
    npm ci 2>/dev/null || npm install
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    yarn install --frozen-lockfile 2>/dev/null || yarn install
  elif [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install
  fi
fi

# Ruby / Bundler.
if [ -f Gemfile ] && command -v bundle >/dev/null 2>&1; then
  bundle install --quiet || true
fi

# Nvim plugin (Lex): submodule init + pinned binary/source fetch.
# Detection signal is shared/lex-deps.json — the version pin file. The
# tooling here mirrors what .github/workflows/test.yml does for CI so a
# cloud session can `bats test/lex_nvim_plugin.bats` without per-test
# manual setup (assumes `nvim` itself is provided by the env image).
if [ -f shared/lex-deps.json ] && command -v jq >/dev/null 2>&1; then
  # comms submodule holds the canonical theme/policy assets; scripts/gen-theme.py
  # and several tests read from comms/shared/... — without it both fail.
  if [ -f .gitmodules ] && [ ! -e comms/README.md ]; then
    git submodule update --init --recursive --quiet || \
      echo "warning: comms submodule init failed — gen-theme.py will fail" >&2
  fi

  # lexd-lsp binary at the pinned version. Tests pick it up via
  # vim.fn.exepath("lexd-lsp"), so installing to /usr/local/bin avoids
  # needing LEX_LSP_PATH in the session. Stamp file gates re-downloads
  # since lexd-lsp has no --version flag.
  LSP_VERSION=$(jq -r '.["lexd-lsp"]' shared/lex-deps.json)
  LSP_REPO=$(jq -r '.["lexd-lsp-repo"]' shared/lex-deps.json)
  LSP_INSTALL=/usr/local/bin/lexd-lsp
  LSP_STAMP=/usr/local/bin/.lexd-lsp.version
  if [ -n "${LSP_VERSION}" ] && [ "${LSP_VERSION}" != "null" ] && \
     [ "$(cat "${LSP_STAMP}" 2>/dev/null)" != "${LSP_VERSION}" ]; then
    LSP_TMP=$(mktemp -d)
    if curl -fsSL "https://github.com/${LSP_REPO}/releases/download/${LSP_VERSION}/lexd-lsp-x86_64-unknown-linux-gnu.tar.gz" \
         -o "${LSP_TMP}/lsp.tgz" 2>/dev/null && \
       tar -xzf "${LSP_TMP}/lsp.tgz" -C "${LSP_TMP}" 2>/dev/null; then
      BIN=$(find "${LSP_TMP}" -name lexd-lsp -type f | head -1)
      if [ -n "${BIN}" ] && install -m 0755 "${BIN}" "${LSP_INSTALL}" 2>/dev/null; then
        echo "${LSP_VERSION}" > "${LSP_STAMP}" 2>/dev/null || true
      else
        echo "warning: lexd-lsp install failed — LSP-dependent tests will fail" >&2
      fi
    else
      echo "warning: lexd-lsp download failed (${LSP_REPO}@${LSP_VERSION})" >&2
    fi
    rm -rf "${LSP_TMP}"
  fi

  # tree-sitter-lex source for the (handful of) tests that opt-in via
  # LEX_TREESITTER_PATH. Land it at /tmp/tree-sitter-lex to match the
  # CI workflow's path so test invocations look identical to CI.
  TS_VERSION=$(jq -r '.["tree-sitter"]' shared/lex-deps.json)
  TS_REPO=$(jq -r '.["tree-sitter-repo"]' shared/lex-deps.json)
  TS_DIR=/tmp/tree-sitter-lex
  TS_STAMP="${TS_DIR}/.version"
  if [ -n "${TS_VERSION}" ] && [ "${TS_VERSION}" != "null" ] && \
     [ "$(cat "${TS_STAMP}" 2>/dev/null)" != "${TS_VERSION}" ]; then
    TS_TMP=$(mktemp -d)
    if curl -fsSL "https://github.com/${TS_REPO}/releases/download/${TS_VERSION}/tree-sitter.tar.gz" \
         -o "${TS_TMP}/ts.tgz" 2>/dev/null; then
      rm -rf "${TS_DIR}"
      mkdir -p "${TS_DIR}"
      if tar -xzf "${TS_TMP}/ts.tgz" -C "${TS_DIR}" 2>/dev/null; then
        echo "${TS_VERSION}" > "${TS_STAMP}" 2>/dev/null || true
      fi
    else
      echo "warning: tree-sitter-lex download failed (${TS_REPO}@${TS_VERSION})" >&2
    fi
    rm -rf "${TS_TMP}"
  fi
fi

# 2. Pre-commit hook wiring (lefthook).
# Binary is installed at env-setup time (arthur-debert/release env/setup.sh);
# this just wires .git/hooks/pre-commit to call it. Errors are surfaced
# loudly — the whole point of the script is the hook install.
if [ -f lefthook.yml ] && command -v lefthook >/dev/null 2>&1; then
  if ! lefthook install; then
    echo "warning: lefthook install failed — pre-commit hook NOT wired" >&2
  fi
fi

exit 0
