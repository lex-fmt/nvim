-- Lex Neovim Plugin
-- ===================
--
-- Main entry point for the Lex language plugin providing:
-- - LSP integration via nvim-lspconfig
-- - Semantic token highlighting (parser-driven, not regex-based)
-- - Filetype detection for .lex files
--
-- See README.lex for user documentation.

local binary_manager = require("lex.binary")
local theme = require("lex.theme")
local debug = require("lex.debug")
local commands = require("lex.commands")

local M = {}

-- Plugin version (lex-lsp version read from shared/lex-deps.json)
M.version = "0.3.3"

-- Read lex-lsp version from shared/lex-deps.json
local function read_lex_deps()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local deps_file = plugin_root .. "/shared/lex-deps.json"

  local file = io.open(deps_file, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, deps = pcall(vim.json.decode, content)
  if not ok or type(deps) ~= "table" then
    return nil
  end

  return deps
end

-- Get pinned lex-lsp version from shared/lex-deps.json
local function get_pinned_lsp_version()
  local deps = read_lex_deps()
  if deps and deps["lex-lsp"] then
    return deps["lex-lsp"]
  end
  -- Fallback if deps file not found
  return "lex-lsp-v0.2.7"
end

-- For backwards compatibility
M.lex_lsp_version = get_pinned_lsp_version()

-- Detect the lex workspace root by looking for the characteristic structure:
-- a directory containing core/, editors/, tools/ subdirectories.
-- Returns nil if not in a lex workspace.
local function detect_lex_workspace()
  local override = vim.env.LEX_WORKSPACE_ROOT
  if override and override ~= "" and vim.fn.isdirectory(override) == 1 then
    return override
  end

  -- Start from plugin directory and look for parent workspace
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local current = plugin_root

  while current ~= "/" and current ~= "" do
    local parent = vim.fn.fnamemodify(current, ":h")
    if
      vim.fn.isdirectory(parent .. "/core") == 1
      and vim.fn.isdirectory(parent .. "/editors") == 1
      and vim.fn.isdirectory(parent .. "/tools") == 1
    then
      return parent
    end
    current = parent
  end

  return nil
end

-- Resolve which lex-lsp binary to execute.
-- Priority:
-- 1. LEX_LSP_PATH env var (explicit override)
-- 2. Workspace binary at {workspace}/target/local/lex-lsp (dev convenience)
-- 3. opts.cmd (user override)
-- 4. Auto-download pinned version
-- 5. Fallback: lex-lsp in PATH
local function resolve_lsp_cmd(opts)
  local is_windows = vim.fn.has("win32") == 1
  local binary_name = is_windows and "lex-lsp.exe" or "lex-lsp"

  -- 1. Environment variable takes precedence (for CI and explicit override)
  local env_path = vim.env.LEX_LSP_PATH
  if env_path and env_path ~= "" then
    if vim.fn.filereadable(env_path) == 1 then
      return { env_path }
    end
    vim.notify(
      string.format("LEX_LSP_PATH set but binary not found: %s", env_path),
      vim.log.levels.WARN,
      { title = "Lex" }
    )
  end

  -- 2. Check for workspace binary (dev mode)
  local workspace = detect_lex_workspace()
  if workspace then
    local workspace_binary = workspace .. "/target/local/" .. binary_name
    if vim.fn.filereadable(workspace_binary) == 1 then
      return { workspace_binary }
    end
    -- Workspace detected but no binary - warn but continue to fallback
    vim.notify(
      string.format(
        "Lex workspace detected at %s but no dev binary found. Run ./scripts/build-local.sh to build it.",
        workspace
      ),
      vim.log.levels.WARN,
      { title = "Lex" }
    )
  end

  -- 3. User opts.cmd override
  if opts.cmd then
    return opts.cmd
  end

  -- 4. Auto-download pinned version
  local desired = opts.lex_lsp_version
  if desired == nil then
    desired = M.lex_lsp_version
  end

  if desired and desired ~= "" then
    local path = binary_manager.ensure_binary(desired)
    if path then
      return { path }
    end
  end

  -- 5. Fallback to PATH
  return { "lex-lsp" }
end

-- Setup function called by lazy.nvim or manual setup
function M.setup(opts)
  opts = opts or {}
  local resolved_cmd = resolve_lsp_cmd(opts)
  local theme_name = opts.theme or "monochrome"

  -- Register .lex filetype
  vim.filetype.add({
    extension = {
      lex = "lex",
    },
  })

  -- Setup LSP if lspconfig is available
  local ok, lspconfig = pcall(require, "lspconfig")
  if ok then
    local configs = require("lspconfig.configs")

    -- Register lex-lsp server config if not already registered
    if not configs.lex_lsp then
      configs.lex_lsp = {
        default_config = {
          cmd = resolved_cmd,
          filetypes = { "lex" },
          root_dir = function(fname)
            return lspconfig.util.find_git_ancestor(fname) or vim.fn.getcwd()
          end,
          settings = opts.settings or {},
        },
      }
    end

    -- Auto-start LSP for .lex files with semantic token support
    local lsp_config = opts.lsp_config or {}
    local user_on_attach = lsp_config.on_attach

    if not lsp_config.cmd then
      lsp_config.cmd = resolved_cmd
    end

    lsp_config.on_attach = function(client, bufnr)
      -- Enable semantic token highlighting
      if client.server_capabilities.semanticTokensProvider then
        vim.lsp.semantic_tokens.start(bufnr, client.id)
        theme.apply(theme_name)
      end

      -- Setup buffer-local keymaps for commands
      commands.setup_keymaps(bufnr)

      -- Preserve user's on_attach callback
      if user_on_attach then
        user_on_attach(client, bufnr)
      end
    end

    lspconfig.lex_lsp.setup(lsp_config)
  end

  -- Setup debug commands
  debug.setup()

  -- Setup user commands (global, not buffer-specific)
  commands.setup()

  -- Setup autocommands for .lex files
  local augroup = vim.api.nvim_create_augroup("LexPlugin", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "lex",
    callback = function()
      -- Comment support - Lex uses annotations for comments
      vim.bo.commentstring = ":: note :: %s"
      vim.bo.comments = ""

      -- Document editing settings - soft wrap at window width
      vim.wo.wrap = true
      vim.wo.linebreak = true
      vim.bo.textwidth = 0
    end,
  })

  -- Disable built-in lex.vim syntax (conflicts with LSP semantic tokens)
  local function disable_lex_syntax()
    if vim.bo.filetype == "lex" and vim.bo.syntax ~= "" then
      vim.bo.syntax = ""
      vim.cmd("syntax clear")
    end
  end

  vim.api.nvim_create_autocmd({ "FileType" }, {
    group = augroup,
    pattern = "lex",
    callback = function()
      vim.schedule(disable_lex_syntax)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "Syntax" }, {
    group = augroup,
    pattern = { "*.lex", "lex" },
    callback = function()
      vim.schedule(disable_lex_syntax)
    end,
  })
end

return M
