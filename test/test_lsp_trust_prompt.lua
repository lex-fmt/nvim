-- Test: lex/trustRequest handler wiring
--
-- Verifies the plugin's setup() wires `trust_prompt.handle` into the
-- LSP client's `handlers["lex/trustRequest"]`, and that the handler
-- with vim.fn.confirm mocked returns the wire shape lexd-lsp expects.
--
-- Doesn't spin up a real lexd-lsp — that path is exercised in the
-- vscode integration suite (test/integration/aa_lsp_trust_prompt.test.ts
-- in lex-fmt/vscode) where the testing framework already supports
-- mocking the modal. Here we cover:
--   1. The wiring (init.lua sets the handler).
--   2. The handler's response for trusted / denied / cancelled
--      with vim.fn.confirm patched, asserting the shape lexd-lsp
--      will see in production.
--
-- Run: nvim --headless -u NONE -l test/test_lsp_trust_prompt.lua

local script_path = debug.getinfo(1, 'S').source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ':p:h')
local plugin_dir = vim.fn.fnamemodify(test_dir, ':h')
vim.opt.rtp:prepend(plugin_dir)

local function assert_equal(a, b, msg)
  if a ~= b then
    error(string.format('%s\n  expected: %s\n  got:      %s', msg, tostring(b), tostring(a)))
  end
end

local function assert_match(haystack, needle, msg)
  if not haystack:find(needle, 1, true) then
    error(string.format('%s\n  expected to contain: %s\n  in: %s', msg, needle, haystack))
  end
end

local tests = {}
local function add_test(name, fn)
  table.insert(tests, { name = name, run = fn })
end

local function fake_params()
  return {
    namespace = 'acme',
    command_string = '/usr/local/bin/acme-handler',
    source = { kind = 'lex_toml', name = 'acme' },
    capability = 'full',
    transport = 'subprocess',
  }
end

-- Drop-in replacement for vim.fn.confirm. `choice` is what the user
-- "clicks" (1 = Trust, 2 = Deny, 0 = cancelled). The test installs
-- this shim, runs trust_prompt.handle, then asserts the response.
local function with_confirm_returning(choice, body)
  local original = vim.fn.confirm
  local seen = {}
  vim.fn.confirm = function(msg, choices, default, type)
    seen.msg = msg
    seen.choices = choices
    seen.default = default
    seen.type = type
    return choice
  end
  local ok, err = pcall(body, seen)
  vim.fn.confirm = original
  if not ok then
    error(err)
  end
end

add_test('handle returns trusted when user clicks Trust (confirm=1)', function()
  local trust_prompt = require('lex.trust_prompt')
  with_confirm_returning(1, function()
    local response = trust_prompt.handle(nil, fake_params(), nil, nil)
    assert_equal(response.decision, 'trusted', 'confirm=1 should map to trusted')
    assert_equal(response.reason, nil, 'trusted has no reason')
  end)
end)

add_test('handle returns denied with reason when user clicks Deny (confirm=2)', function()
  local trust_prompt = require('lex.trust_prompt')
  with_confirm_returning(2, function()
    local response = trust_prompt.handle(nil, fake_params(), nil, nil)
    assert_equal(response.decision, 'denied', 'confirm=2 should map to denied')
    assert_match(response.reason, 'acme', 'reason names the namespace')
    assert_match(response.reason, 'denied trust', 'reason explains the denial')
  end)
end)

add_test('handle returns denied when user dismisses (confirm=0)', function()
  -- vim.fn.confirm returns 0 for Esc / outside-click. Fail-closed:
  -- a closed prompt must NOT silently grant trust — even though
  -- the lex-side has its own 60s timeout, the editor-side should
  -- still produce a valid denial response.
  local trust_prompt = require('lex.trust_prompt')
  with_confirm_returning(0, function()
    local response = trust_prompt.handle(nil, fake_params(), nil, nil)
    assert_equal(response.decision, 'denied', 'cancelled should map to denied')
    assert_match(response.reason, 'dismissed', 'reason mentions dismissal')
  end)
end)

add_test('handle composes a meaningful prompt for vim.fn.confirm', function()
  local trust_prompt = require('lex.trust_prompt')
  with_confirm_returning(2, function(seen)
    trust_prompt.handle(nil, fake_params(), nil, nil)
    assert_match(seen.msg, '"acme"', 'prompt names the namespace')
    assert_match(seen.msg, '/usr/local/bin/acme-handler', 'prompt shows command')
    assert_match(seen.msg, 'lex.toml', 'prompt describes the source')
    assert_match(seen.msg, 'fs and/or net', 'prompt describes capability')
    -- Choices are Trust + Deny; default highlight on Deny so that
    -- accidental Enter doesn't grant trust.
    assert_match(seen.choices, '&Trust', 'choices include Trust')
    assert_match(seen.choices, '&Deny', 'choices include Deny')
    assert_equal(seen.default, 2, 'Deny is the default to fail-closed on accidental Enter')
  end)
end)

--- Stub lspconfig + lspconfig.configs so we can call lex.setup()
--- without a real LSP server. The stub captures the config that
--- lex.setup() passes into `lspconfig.lex_lsp.setup(...)`, so the
--- test can assert what handlers / on_attach hooks the plugin
--- registered.
local function with_stubbed_lspconfig(body)
  local captured = {}
  local original_loaded_lspconfig = package.loaded['lspconfig']
  local original_loaded_configs = package.loaded['lspconfig.configs']
  local original_loaded_lex = package.loaded['lex']

  package.loaded['lspconfig'] = {
    util = {
      find_git_ancestor = function(_)
        return vim.fn.getcwd()
      end,
    },
    lex_lsp = {
      setup = function(cfg)
        captured.config = cfg
      end,
    },
  }
  package.loaded['lspconfig.configs'] = {}
  -- Force lex/init to re-require lspconfig via our stub on next
  -- require('lex').
  package.loaded['lex'] = nil

  local ok, err = pcall(body, captured)

  package.loaded['lspconfig'] = original_loaded_lspconfig
  package.loaded['lspconfig.configs'] = original_loaded_configs
  package.loaded['lex'] = original_loaded_lex

  if not ok then
    error(err)
  end
end

add_test('lex.setup wires trust_prompt.handle into lsp_config.handlers', function()
  local trust_prompt = require('lex.trust_prompt')
  with_stubbed_lspconfig(function(captured)
    require('lex').setup({})
    assert_equal(
      captured.config and captured.config.handlers
        and captured.config.handlers['lex/trustRequest'],
      trust_prompt.handle,
      'init.lua should register trust_prompt.handle as lex/trustRequest handler'
    )
  end)
end)

add_test('lex.setup preserves a user-supplied lex/trustRequest handler', function()
  -- The plugin must NOT clobber a user-supplied handler — same
  -- on_attach convention applies to handlers. Test that a
  -- pre-set lex/trustRequest is respected.
  with_stubbed_lspconfig(function(captured)
    local user_handler = function()
      return { decision = 'denied', reason = 'user override' }
    end
    require('lex').setup({
      lsp_config = {
        handlers = { ['lex/trustRequest'] = user_handler },
      },
    })
    assert_equal(
      captured.config and captured.config.handlers
        and captured.config.handlers['lex/trustRequest'],
      user_handler,
      'a user-supplied lex/trustRequest handler must NOT be overwritten'
    )
  end)
end)

local function run_tests()
  for _, test in ipairs(tests) do
    local ok, err = xpcall(test.run, debug.traceback)
    if not ok then
      print('TEST_FAILED: ' .. test.name .. ' -> ' .. err)
      os.exit(1)
    end
  end
  print('TEST_PASSED: trust prompt LSP wiring')
  os.exit(0)
end

run_tests()
