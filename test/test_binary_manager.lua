-- Headless test to exercise the lex.binary helper without hitting the network.
-- The script is executed via `nvim --headless -u NONE -l this_file.lua` by the
-- Bats suite and prints TEST_PASSED/TEST_FAILED markers for CI consumption.

local script_path = debug.getinfo(1, 'S').source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ':p:h')
local plugin_dir = vim.fn.fnamemodify(test_dir, ':h')
vim.opt.rtp:prepend(plugin_dir)

local uv = vim.loop
local binary = require('lex.binary')

local is_windows = uv.os_uname().sysname:lower():find('windows') ~= nil
local suffix = is_windows and '.exe' or ''
local temp_roots = {}

local function temp_plugin_root()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  table.insert(temp_roots, dir)
  return dir
end

local function cleanup()
  for _, dir in ipairs(temp_roots) do
    pcall(vim.fn.delete, dir, 'rf')
  end
end

local function assert_true(value, msg)
  if not value then
    error(msg)
  end
end

local function make_fake_binary(path)
  local fh = assert(io.open(path, 'w'))
  fh:write('#!/bin/sh\nexit 0\n')
  fh:close()
  if not is_windows then
    vim.fn.setfperm(path, 'rwxr-xr-x')
  end
end

local tests = {}

local function add_test(name, fn)
  table.insert(tests, { name = name, run = fn })
end

add_test('reuses existing binary', function()
  local root = temp_plugin_root()
  local version = 'v9.9.9'
  local bin_dir = root .. '/bin'
  vim.fn.mkdir(bin_dir, 'p')
  local existing = string.format('%s/lexd-lsp-%s%s', bin_dir, version, suffix)
  make_fake_binary(existing)
  binary._set_test_overrides({ plugin_root = root })
  local resolved = binary.ensure_binary(version)
  assert_true(resolved == existing, 'should reuse existing binary for ' .. version)
end)

add_test('selects architecture specific assets', function()
  local select_asset = binary._select_asset_for_testing
  assert_true(select_asset('darwin', 'arm64').filename == 'lexd-lsp-aarch64-apple-darwin.tar.gz', 'mac arm64 asset mismatch')
  assert_true(select_asset('darwin', 'x86_64').filename == 'lexd-lsp-x86_64-apple-darwin.tar.gz', 'mac amd64 asset mismatch')
  assert_true(select_asset('linux', 'aarch64').filename == 'lexd-lsp-aarch64-unknown-linux-gnu.tar.gz', 'linux arm64 asset mismatch')
  assert_true(select_asset('linux', 'x86_64').filename == 'lexd-lsp-x86_64-unknown-linux-gnu.tar.gz', 'linux amd64 asset mismatch')
  -- Note: arm64 Windows not currently built, so we only test amd64
  assert_true(select_asset('windows', 'amd64').filename == 'lexd-lsp-x86_64-pc-windows-msvc.zip', 'windows amd64 asset mismatch')
end)

add_test('windows arm64 falls back to amd64 asset', function()
  -- arm64 Windows isn't built; the table lookup misses and we fall
  -- through to the amd64 zip rather than returning nil. Documenting
  -- the contract here so a future arm64 build doesn't silently change
  -- platform behaviour for windows arm64 users.
  local select_asset = binary._select_asset_for_testing
  local asset = select_asset('windows', 'arm64')
  assert_true(asset ~= nil, 'windows/arm64 should fall back, not return nil')
  assert_true(asset.filename == 'lexd-lsp-x86_64-pc-windows-msvc.zip', 'windows arm64 should resolve to amd64 zip')
  assert_true(asset.kind == 'zip', 'windows fallback should still be zip-kind')
end)

add_test('selects amd64 when arch is unknown or empty', function()
  -- normalized_arch defaults to amd64 for anything it can't classify.
  -- This is the hot path for a user on (say) an i686 box or a kernel
  -- whose `uname -m` we don't recognise — we'd rather try amd64 than
  -- crash with nil.
  local select_asset = binary._select_asset_for_testing
  assert_true(select_asset('linux', 'i686').filename == 'lexd-lsp-x86_64-unknown-linux-gnu.tar.gz', 'unknown arch should pick amd64')
  assert_true(select_asset('linux', '').filename == 'lexd-lsp-x86_64-unknown-linux-gnu.tar.gz', 'empty arch should pick amd64')
  assert_true(select_asset('linux', nil).filename == 'lexd-lsp-x86_64-unknown-linux-gnu.tar.gz', 'nil arch should pick amd64')
end)

add_test('returns nil for unsupported OS', function()
  -- BSDs aren't in the platform table. ensure_binary's caller treats a
  -- nil asset as "no auto-download path" and falls back to lexd-lsp on
  -- PATH — that's the contract we want to preserve.
  local select_asset = binary._select_asset_for_testing
  assert_true(select_asset('freebsd', 'amd64') == nil, 'freebsd has no asset')
  assert_true(select_asset('', 'amd64') == nil, 'empty os has no asset')
end)

add_test('ensure_binary rejects nil and empty version', function()
  -- Setup flow can hit this when shared/lex-deps.json is missing AND
  -- the user passed lex_lsp_version = "". ensure_binary must refuse so
  -- resolve_lsp_cmd falls back to `lexd-lsp` on PATH rather than
  -- writing the empty string into a "lexd-lsp-" filename.
  assert_true(binary.ensure_binary(nil) == nil, 'nil version returns nil')
  assert_true(binary.ensure_binary('') == nil, 'empty version returns nil')
end)

add_test('ensure_binary returns existing file path verbatim', function()
  -- When opts.lex_lsp_version is itself a path to a binary (the
  -- LEX_LSP_PATH-style explicit override), ensure_binary short-circuits
  -- and returns it without trying to interpret it as a tag. Guards
  -- against a regression where the path-as-version case gets confused
  -- with a missing-binary download attempt.
  local tmp = vim.fn.tempname()
  make_fake_binary(tmp)
  -- No test overrides: we want the real filereadable check.
  local resolved = binary.ensure_binary(tmp)
  assert_true(resolved == tmp, 'existing path should pass through unchanged')
  vim.fn.delete(tmp)
end)

add_test('finds extracted binary inside nested directories', function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local nested = string.format('%s/lexd-lsp-test', tmp)
  vim.fn.mkdir(nested, 'p')
  local expected = string.format('%s/lexd-lsp', nested)
  make_fake_binary(expected)
  local found = binary._find_binary_in_tmpdir_for_testing(tmp, 'lexd-lsp')
  assert_true(found == expected, 'should locate binary within archive subdirectories')
  vim.fn.delete(tmp, 'rf')
end)

add_test('downloads missing version', function()
  local root = temp_plugin_root()
  local version = 'v1.2.3'
  local downloads = {}
  binary._set_test_overrides({
    plugin_root = root,
    download_release = function(tag, dest)
      table.insert(downloads, { tag = tag, dest = dest })
      make_fake_binary(dest)
      return dest
    end,
  })
  local resolved = binary.ensure_binary(version)
  assert_true(#downloads == 1, 'should trigger a download when binary is missing')
  assert_true(downloads[1].tag == version, 'download should use requested version')
  assert_true(resolved == downloads[1].dest, 'ensure_binary should return downloaded path')
  assert_true(vim.fn.filereadable(resolved) == 1, 'downloaded binary must exist')
end)

add_test('falls back to latest release', function()
  local root = temp_plugin_root()
  local requested = 'v-does-not-exist'
  local fallback = 'v0.1.0'
  local download_tags = {}
  local latest_calls = 0
  binary._set_test_overrides({
    plugin_root = root,
    download_release = function(tag, dest)
      table.insert(download_tags, tag)
      if tag == requested then
        return nil, 'missing'
      end
      make_fake_binary(dest)
      return dest
    end,
    latest_tag = function()
      latest_calls = latest_calls + 1
      return fallback
    end,
  })
  local resolved = binary.ensure_binary(requested)
  assert_true(latest_calls == 1, 'latest_tag should be consulted when primary download fails')
  assert_true(#download_tags == 2, 'should attempt download twice (requested + fallback)')
  assert_true(download_tags[1] == requested and download_tags[2] == fallback, 'download order mismatch')
  assert_true(resolved ~= nil, 'fallback download should succeed')
end)

add_test('propagates failure notifications', function()
  local root = temp_plugin_root()
  local version = 'vbroken'
  local notifications = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, opts)
    table.insert(notifications, { msg = msg, level = level, opts = opts })
  end
  binary._set_test_overrides({
    plugin_root = root,
    download_release = function()
      return nil, 'network error'
    end,
    latest_tag = function()
      return nil
    end,
  })
  local resolved = binary.ensure_binary(version)
  vim.notify = orig_notify
  assert_true(resolved == nil, 'ensure_binary should return nil on unrecoverable failure')
  assert_true(#notifications >= 1, 'user should be notified when downloads fail')
  local level = notifications[1].level
  assert_true(level == vim.log.levels.ERROR, 'notification should be marked as error')
end)

local function run_tests()
  for _, test in ipairs(tests) do
    local ok, err = xpcall(test.run, debug.traceback)
    binary._reset_test_overrides()
    if not ok then
      cleanup()
      print('TEST_FAILED: ' .. test.name .. ' -> ' .. err)
      os.exit(1)
    end
  end
  cleanup()
  print('TEST_PASSED: binary manager scenarios')
  os.exit(0)
end

run_tests()
