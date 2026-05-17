#!/usr/bin/env bash
# scripts/setup-dev-env.sh — per-session dev-environment setup, invoked by
# the SessionStart hook in .claude/settings.json.
#
# Source of truth: arthur-debert/release templates/setup-dev-env.sh.
# Re-sync via the gh-repo-setup skill (or by copying this file verbatim).
# Repos that need project-specific extras (Xvfb daemon, pinned-binary
# fetch, extra rustup targets, etc.) append them below the marker at the
# bottom — anything above it is rsync'd from the template.
#
# Cloud-only: local sessions exit early (devs already have their env).
# Detects stack by filesystem signals — handles rust, node, ruby, python,
# and consumers with no project deps (just lefthook / hand-rolled hook
# wiring).
#
# Idempotent — safe to re-run. Errors are best-effort: a failure in one
# step does not abort the rest (transient registry hiccups shouldn't
# block the lefthook install).

set -euo pipefail

# Cloud-only gate. Local sessions already have their env set up.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

# --- 1. Universal git hygiene --------------------------------------------
# Cloud clones are shallow; restore submodule content and release tags.
# Submodule update is a no-op when in sync; tag fetch is one round-trip.

if [ -f .gitmodules ]; then
  git submodule update --init --recursive --quiet || true
fi
git fetch --tags --quiet origin || true

# --- 2. Project dep cache ------------------------------------------------
# Pick the right tool based on lockfile / manifest. Per stack, idempotent.

# Rust: cargo fetch with --locked so we don't silently mutate Cargo.lock.
if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  cargo fetch --locked --quiet || true
fi

# Node (npm/yarn/pnpm). We deliberately do NOT guard on `! -d node_modules`:
# the env-snapshot caches a node_modules paired with a previous branch's
# lockfile, and a feature branch that bumps the lockfile (Playwright is
# the canonical case) drifts silently. Re-installing when already in sync
# is ~2s; chasing a stale lockfile bug is hours. Pay the two seconds.
if [ -f package.json ]; then
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

# Python / pip + venv. Only initialise if .venv missing — pip install is
# slower than node/cargo and the guard wins more than it costs.
if [ -f pyproject.toml ] && [ ! -d .venv ] && command -v python3 >/dev/null 2>&1; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip --quiet || true
  .venv/bin/pip install -e '.[dev]' --quiet 2>/dev/null \
    || .venv/bin/pip install -e . --quiet 2>/dev/null \
    || true
fi

# --- 3. Pre-commit hook wiring -------------------------------------------
# Default: lefthook (binary installed at env-setup time). Fallback for
# repos that ship a hand-rolled scripts/pre-commit instead (zed-lex,
# tree-sitter-lex pattern): symlink it into .git/hooks/.

if [ -f lefthook.yml ] && command -v lefthook >/dev/null 2>&1; then
  if ! lefthook install >/dev/null; then
    echo "warning: lefthook install failed — pre-commit hook NOT wired" >&2
  fi
elif [ -x scripts/pre-commit ]; then
  mkdir -p .git/hooks
  ln -sf ../../scripts/pre-commit .git/hooks/pre-commit
fi

# --- 4. Project-local extras ---------------------------------------------
# Everything above this marker is the canonical cross-repo setup-dev-env.sh
# from arthur-debert/release templates/setup-dev-env.sh. Do NOT modify it
# in-place; consumers append project-specific steps BELOW this marker.
# (See e.g. lex-fmt/lexed for an Xvfb start, lex-fmt/nvim for pinned-bin
# fetches.)


# Nvim plugin (Lex): pinned binary/source fetch.
# Detection signal is shared/lex-deps.json — the version pin file. The
# tooling here mirrors what .github/workflows/test.yml does for CI so a
# cloud session can `bats test/lex_nvim_plugin.bats` without per-test
# manual setup (assumes `nvim` itself is provided by the env image).
if [ -f shared/lex-deps.json ] && command -v jq >/dev/null 2>&1; then
  LSP_VERSION=$(jq -r '.["lexd-lsp"]' shared/lex-deps.json)
  LSP_REPO=$(jq -r '.["lexd-lsp-repo"]' shared/lex-deps.json)

  case "$(uname -m)" in
    x86_64|amd64) LSP_ARCH=x86_64-unknown-linux-gnu ;;
    *) LSP_ARCH=""; echo "warning: lexd-lsp not available for $(uname -m); skipping" >&2 ;;
  esac

  if [ -w /usr/local/bin ]; then
    LSP_INSTALL_DIR=/usr/local/bin
  else
    LSP_INSTALL_DIR="${HOME}/.local/bin"
    mkdir -p "${LSP_INSTALL_DIR}"
  fi
  LSP_INSTALL="${LSP_INSTALL_DIR}/lexd-lsp"
  LSP_STAMP="${LSP_INSTALL_DIR}/.lexd-lsp.version"

  if [ -n "${LSP_ARCH}" ] && [ -n "${LSP_VERSION}" ] && [ "${LSP_VERSION}" != "null" ] && \
     [ "$(cat "${LSP_STAMP}" 2>/dev/null)" != "${LSP_VERSION}" ]; then
    LSP_TMP=$(mktemp -d)
    if curl -fsSL "https://github.com/${LSP_REPO}/releases/download/${LSP_VERSION}/lexd-lsp-${LSP_ARCH}.tar.gz" \
         -o "${LSP_TMP}/lsp.tgz" && \
       tar -xzf "${LSP_TMP}/lsp.tgz" -C "${LSP_TMP}"; then
      BIN=$(find "${LSP_TMP}" -name lexd-lsp -type f | head -1)
      if [ -n "${BIN}" ] && install -m 0755 "${BIN}" "${LSP_INSTALL}"; then
        echo "${LSP_VERSION}" > "${LSP_STAMP}" || true
      else
        echo "warning: lexd-lsp install failed — LSP-dependent tests will fail" >&2
      fi
    else
      echo "warning: lexd-lsp download failed (${LSP_REPO}@${LSP_VERSION})" >&2
    fi
    rm -rf "${LSP_TMP}"
  fi

  TS_VERSION=$(jq -r '.["tree-sitter"]' shared/lex-deps.json)
  TS_REPO=$(jq -r '.["tree-sitter-repo"]' shared/lex-deps.json)
  TS_DIR=/tmp/tree-sitter-lex
  TS_STAMP="${TS_DIR}/.version"
  if [ -n "${TS_VERSION}" ] && [ "${TS_VERSION}" != "null" ] && \
     [ "$(cat "${TS_STAMP}" 2>/dev/null)" != "${TS_VERSION}" ]; then
    TS_TMP=$(mktemp -d)
    if curl -fsSL "https://github.com/${TS_REPO}/releases/download/${TS_VERSION}/tree-sitter.tar.gz" \
         -o "${TS_TMP}/ts.tgz"; then
      rm -rf "${TS_DIR}"
      mkdir -p "${TS_DIR}"
      if tar -xzf "${TS_TMP}/ts.tgz" -C "${TS_DIR}"; then
        echo "${TS_VERSION}" > "${TS_STAMP}" || true
      fi
    else
      echo "warning: tree-sitter-lex download failed (${TS_REPO}@${TS_VERSION})" >&2
    fi
    rm -rf "${TS_TMP}"
  fi

  # Export LEX_TREESITTER_PATH for the test suite.
  # test_treesitter / test_injections / test_table_highlighting read
  # vim.env.LEX_TREESITTER_PATH; without it they print TEST_SKIPPED and
  # the bats matcher (which requires "TEST_PASSED") flips 3 of 23 tests
  # to failed. CI sets the var as a job-level env (.github/workflows/
  # test.yml). Cloud sessions need the equivalent on two layers:
  #   1. .claude/settings.json `env` — propagates the var into the
  #      Claude Code Bash tool's non-interactive subshells (which do
  #      not source ~/.bashrc).
  #   2. The marker-guarded bashrc append below — for humans who shell
  #      into the cloud container interactively.
  # Idempotent: the marker guard means re-runs are no-ops.
  # Guard on TS_STAMP, not just [ -d "${TS_DIR}" ]: a failed tar leaves
  # TS_DIR existing but empty (mkdir runs before the extract), and we
  # don't want to export LEX_TREESITTER_PATH pointing at an invalid tree.
  # TS_STAMP is only written after a successful extract and persists
  # across cached re-runs, so it works as a success sentinel either way.
  if [ -f "${TS_STAMP}" ] && [ -n "${HOME:-}" ] && [ -w "${HOME}" ]; then
    BASHRC="${HOME}/.bashrc"
    MARKER="# >>> lex-fmt/nvim setup-dev-env.sh >>>"
    if ! grep -qF "${MARKER}" "${BASHRC}" 2>/dev/null; then
      {
        echo ""
        echo "${MARKER}"
        echo "export LEX_TREESITTER_PATH=\"${TS_DIR}\""
        echo "# <<< lex-fmt/nvim setup-dev-env.sh <<<"
      } >> "${BASHRC}" || true
    fi
  fi
fi

exit 0
