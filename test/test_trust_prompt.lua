-- Headless tests for lua/lex/trust_prompt.lua. Exercises the pure
-- formatter helpers and the response builder; the vim.fn.confirm-driven
-- handle() function isn't covered here (would need an interactive
-- terminal). The interactive path is just `confirm() → response_for_choice()`,
-- so covering the latter exhaustively is enough.

local script_path = debug.getinfo(1, 'S').source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ':p:h')
local plugin_dir = vim.fn.fnamemodify(test_dir, ':h')
vim.opt.rtp:prepend(plugin_dir)

local trust_prompt = require('lex.trust_prompt')

local function assert_match(haystack, needle, msg)
  if not haystack:find(needle, 1, true) then
    error(string.format('%s\n  expected to contain: %s\n  in: %s', msg, needle, haystack))
  end
end

local function assert_equal(a, b, msg)
  if a ~= b then
    error(string.format('%s\n  expected: %s\n  got:      %s', msg, tostring(b), tostring(a)))
  end
end

local tests = {}
local function add_test(name, fn)
  table.insert(tests, { name = name, run = fn })
end

add_test('describe_source labels lex_toml entries', function()
  local label = trust_prompt.describe_source({ kind = 'lex_toml', name = 'acme' })
  assert_match(label, 'lex.toml', 'label should mention lex.toml')
  assert_match(label, '"acme"', 'label should quote the namespace name')
end)

add_test('describe_source labels local_file paths', function()
  local label = trust_prompt.describe_source({ kind = 'local_file', path = '/tmp/schemas/acme' })
  assert_match(label, '/tmp/schemas/acme', 'label should include the path')
  assert_match(label, 'local schema directory', 'label should say "local schema directory"')
end)

add_test('describe_source labels cache_only with uri', function()
  local label = trust_prompt.describe_source({ kind = 'cache_only', uri = 'github:acme/lex@v1' })
  assert_match(label, 'github:acme/lex@v1', 'label should include the URI')
end)

add_test('describe_source forward-compatible on unknown kinds', function()
  -- Wire spec says new source variants are non-breaking; the editor
  -- must not crash on a kind it doesn't recognise.
  local label = trust_prompt.describe_source({ kind = 'future_kind' })
  assert_match(label, 'future_kind', 'unknown kind should pass through')
end)

add_test('describe_source handles nil and empty input', function()
  assert_equal(trust_prompt.describe_source(nil), 'unknown source', 'nil source')
  assert_equal(trust_prompt.describe_source({}), 'unknown source', 'empty table')
end)

add_test('describe_capability labels pure with sandbox note', function()
  local label = trust_prompt.describe_capability('pure')
  assert_match(label, 'pure', 'label includes "pure"')
  assert_match(label, 'not yet sandbox-enforced', 'label notes the deferred sandbox')
end)

add_test('describe_capability labels full', function()
  local label = trust_prompt.describe_capability('full')
  assert_match(label, 'full', 'label includes "full"')
  assert_match(label, 'fs and/or net', 'label describes fs/net access')
end)

add_test('describe_capability passes through unknown values', function()
  -- Same forward-compat guarantee for capability values.
  assert_equal(
    trust_prompt.describe_capability('fs_read'),
    'fs_read',
    'unknown capability should pass through verbatim'
  )
end)

add_test('format_message includes namespace, source, command, capability', function()
  local msg = trust_prompt.format_message({
    namespace = 'acme',
    command_string = '/usr/local/bin/acme-handler --serve',
    source = { kind = 'lex_toml', name = 'acme' },
    capability = 'full',
    transport = 'subprocess',
  })
  assert_match(msg, '"acme"', 'message names the namespace')
  assert_match(msg, '/usr/local/bin/acme-handler --serve', 'message shows command string')
  assert_match(msg, 'lex.toml', 'message describes the source')
  assert_match(msg, 'fs and/or net', 'message describes capabilities')
end)

add_test('response_for_choice maps confirm 1 to trusted', function()
  local r = trust_prompt.response_for_choice('acme', 1)
  assert_equal(r.decision, 'trusted', 'confirm=1 should be trusted')
  assert_equal(r.reason, nil, 'trusted has no reason')
end)

add_test('response_for_choice maps confirm 2 to denied with reason', function()
  local r = trust_prompt.response_for_choice('acme', 2)
  assert_equal(r.decision, 'denied', 'confirm=2 should be denied')
  assert_match(r.reason, 'acme', 'reason should name the namespace')
  assert_match(r.reason, 'denied trust', 'reason should explain the denial')
end)

add_test('response_for_choice maps confirm 0 (cancelled) to denied', function()
  -- vim.fn.confirm returns 0 for Esc / outside-click. Fail-closed: a
  -- closed prompt must NOT silently grant trust.
  local r = trust_prompt.response_for_choice('acme', 0)
  assert_equal(r.decision, 'denied', 'cancelled prompt should be denied')
  assert_match(r.reason, 'dismissed', 'reason should mention dismissal')
end)

add_test('response_for_choice handles nil namespace', function()
  -- Defensive: if the LSP somehow sent a request without namespace,
  -- the diagnostic shouldn't crash trying to format the reason.
  local r = trust_prompt.response_for_choice(nil, 2)
  assert_equal(r.decision, 'denied', 'still denies')
  assert_match(r.reason, '(unknown)', 'reason notes unknown namespace')
end)

local function run_tests()
  for _, test in ipairs(tests) do
    local ok, err = xpcall(test.run, debug.traceback)
    if not ok then
      print('TEST_FAILED: ' .. test.name .. ' -> ' .. err)
      os.exit(1)
    end
  end
  print('TEST_PASSED: trust prompt scenarios')
  os.exit(0)
end

run_tests()
