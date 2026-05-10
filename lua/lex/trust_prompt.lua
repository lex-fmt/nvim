-- lua/lex/trust_prompt.lua
--
-- Handler for the `lex/trustRequest` LSP custom request fired by
-- lexd-lsp during extension boot when a subprocess handler hasn't been
-- pinned in `<workspace>/.lex/trust.json`. Wire shape mirrors
-- `crates/lex-lsp/src/trust_prompt.rs` in lex-fmt/lex (γ phase, lex#549).
--
-- Behaviour: blocks the LSP boot with a `vim.fn.confirm` modal asking
-- the user to Trust or Deny. Choice is sent back as the request
-- response and pinned by the trust gate for subsequent sessions.
-- Cancelling the prompt counts as denied (fail-closed).
--
-- This module is wired into the per-client `handlers` table by
-- `lua/lex/init.lua` so each LSP buffer gets its own handler. The
-- module-level `M.handle` function is exposed for unit testing the
-- pure formatters.

local M = {}

--- Format the modal title shown by vim.fn.confirm.
--- @param params table TrustRequestParams from the LSP server.
--- @return string
function M.format_message(params)
  return string.format(
    'Lex extension namespace "%s" wants to run a subprocess handler.\n\nSource: %s\nCommand: %s\nCapabilities: %s\n\nTrusting will allow this binary to run on this workspace\'s documents until you revoke it. Denying registers the namespace schema-only — pre-validation still runs but no handler is invoked.',
    params.namespace or "(unknown)",
    M.describe_source(params.source),
    params.command_string or "(unknown)",
    M.describe_capability(params.capability)
  )
end

--- Render a TrustRequestParams source into a human-readable label.
--- Forward-compatible: unknown source kinds render their raw `kind` string.
--- @param source table|nil
--- @return string
function M.describe_source(source)
  if not source or type(source) ~= "table" then
    return "unknown source"
  end
  local kind = source.kind
  if kind == "lex_toml" then
    return string.format('lex.toml [labels] entry "%s"', source.name or "(unnamed)")
  elseif kind == "local_file" then
    return string.format("local schema directory %s", source.path or "(no path)")
  elseif kind == "cache_only" then
    return string.format("cached fetch from %s", source.uri or "(no uri)")
  else
    return tostring(kind or "unknown source")
  end
end

--- Render a capability string into a human-readable label.
--- Forward-compatible: unknown values pass through.
--- @param capability string|nil
--- @return string
function M.describe_capability(capability)
  if capability == "pure" then
    return "pure (no fs / no net) — declared but not yet sandbox-enforced"
  elseif capability == "full" then
    return "full (fs and/or net access)"
  elseif capability == nil or capability == "" then
    return "unknown"
  else
    return tostring(capability)
  end
end

--- Build the LSP response for the user's confirm choice.
--- @param namespace string Namespace from the request, used in deny reasons.
--- @param confirm_result integer Return value from vim.fn.confirm:
---   1 = Trust, 2 = Deny, 0 = Cancelled (Esc / outside-click).
--- @return table TrustResponse — { decision, reason? }.
function M.response_for_choice(namespace, confirm_result)
  if confirm_result == 1 then
    return { decision = "trusted" }
  elseif confirm_result == 2 then
    return {
      decision = "denied",
      reason = string.format(
        "User denied trust for namespace `%s` in this workspace.",
        namespace or "(unknown)"
      ),
    }
  else
    -- 0 (cancelled) and any unexpected value fall through to denied
    -- — fail-closed, never silently grant trust.
    return {
      decision = "denied",
      reason = string.format(
        "Trust prompt for namespace `%s` was dismissed without a decision.",
        namespace or "(unknown)"
      ),
    }
  end
end

--- LSP request handler for `lex/trustRequest`. Signature matches the
--- nvim 0.10+ `vim.lsp.handlers` shape for server-initiated requests:
--- `function(err, params, ctx, config) -> (result, err)`.
---
--- @param _err any Always nil for incoming server requests.
--- @param params table TrustRequestParams payload.
--- @param _ctx table LSP context (unused).
--- @param _config table|nil Per-handler config (unused).
--- @return table TrustResponse, nil
function M.handle(_err, params, _ctx, _config)
  local message = M.format_message(params or {})
  -- vim.fn.confirm is synchronous and blocks the LSP boot for a few
  -- seconds at most. The lex-side has a 60s timeout on the prompt, so
  -- if the user is slow the boot still recovers gracefully (denied
  -- with a "timed out" diagnostic). 2 = default-Deny so accidental
  -- Enter doesn't grant trust.
  local choice = vim.fn.confirm(message, "&Trust\n&Deny", 2, "Question")
  return M.response_for_choice(params and params.namespace, choice), nil
end

return M
