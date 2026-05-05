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
local lex_debug = require("lex.debug")
local commands = require("lex.commands")
local treesitter = require("lex.treesitter")

local M = {}

-- Plugin version. Bump alongside the git tag in scripts/create-release.
-- (Not the LSP version — that's M.lex_lsp_version, read from shared/lex-deps.json below.)
M.version = "0.8.0"

-- Get the plugin root directory
local function get_plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h")
end

-- Read lexd-lsp version from shared/lex-deps.json
local function read_lex_deps()
  local plugin_root = get_plugin_root()
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

-- Get pinned lexd-lsp version from shared/lex-deps.json
local function get_pinned_lsp_version()
  local deps = read_lex_deps()
  if deps and deps["lexd-lsp"] then
    return deps["lexd-lsp"]
  end
  -- Fallback if deps file not found
  return "v0.3.0"
end

M.lex_lsp_version = get_pinned_lsp_version()

-- Resolve which lexd-lsp binary to execute.
-- Priority:
-- 1. LEX_LSP_PATH env var (explicit override, e.g. for local dev builds)
-- 2. opts.cmd (user override)
-- 3. Auto-download pinned version
-- 4. Fallback: lexd-lsp in PATH
local function resolve_lsp_cmd(opts)
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

  -- 2. User opts.cmd override
  if opts.cmd then
    return opts.cmd
  end

  -- 3. Auto-download pinned version
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

  -- 4. Fallback to PATH
  return { "lexd-lsp" }
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

    -- Register lexd-lsp server config if not already registered
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
      -- Enable semantic token highlighting.
      -- `vim.lsp.semantic_tokens.enable`'s filter table treats `bufnr`
      -- and `client_id` as mutually exclusive (hard-errors as of
      -- Neovim 0.12.1). Pass only `bufnr` — on_attach already fires
      -- per (client, buffer) and is gated on the client's semantic
      -- tokens capability, so scoping to the buffer is sufficient.
      if client.server_capabilities.semanticTokensProvider then
        vim.lsp.semantic_tokens.enable(true, { bufnr = bufnr })
        theme.apply(theme_name)
      end

      -- Make diagnostics visible by default, scoped to lexd-lsp's
      -- namespace so we don't override the user's global config or
      -- step on other language servers in the same nvim. Without
      -- this the LSP's diagnostics arrive (vim.diagnostic.get(0)
      -- returns them) but render nothing on screen unless the user
      -- has called vim.diagnostic.config({...}) themselves.
      --
      -- We deliberately only flip what's *enabled* (virtual_text,
      -- signs, underline) and leave highlight groups, sign chars,
      -- and message formatting to the user's colorscheme. Lex-themed
      -- diagnostics (monochrome intensity tiers, custom sign chars)
      -- are a separate opt-in design choice, not the default.
      if vim.lsp.diagnostic and vim.lsp.diagnostic.get_namespace then
        local ns = vim.lsp.diagnostic.get_namespace(client.id)
        vim.diagnostic.config({
          virtual_text = true,
          signs = true,
          underline = true,
          severity_sort = true,
          update_in_insert = false,
        }, ns)
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

  -- Register file icon with nvim-web-devicons if available
  local icons_ok, icons = pcall(require, "nvim-web-devicons")
  if icons_ok then
    icons.set_icon({
      lex = {
        icon = "⬡",
        color = "#231f20",
        cterm_color = "235",
        name = "Lex",
      },
    })
  end

  -- Setup tree-sitter (parser + highlighting + injections + folds)
  local ts_opts = opts.treesitter
  local ts_active = false
  if ts_opts ~= false then
    ts_active = treesitter.setup(type(ts_opts) == "table" and ts_opts or {})
    if ts_active then
      theme.apply_treesitter(theme_name)
    end
  end

  -- Setup debug commands
  lex_debug.setup()

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

      -- Tree-sitter folding (sessions, verbatim blocks, definitions, etc.)
      if ts_active then
        vim.wo.foldmethod = "expr"
        vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.wo.foldlevel = 99 -- start with all folds open
      end
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

  -- Opt-in format-on-save: `lex.setup({ format_on_save = true })` registers
  -- a BufWritePre autocmd that runs `vim.lsp.buf.format` on .lex buffers.
  -- Off by default so users who don't want it don't get it. The formatter
  -- target is the `lex_lsp` client (by name), so other LSPs that happen to
  -- attach to the buffer don't race for the format.
  if opts.format_on_save then
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = augroup,
      pattern = "*.lex",
      callback = function(ev)
        vim.lsp.buf.format({
          bufnr = ev.buf,
          name = "lex_lsp",
          async = false,
        })
      end,
    })
  end
end

return M
