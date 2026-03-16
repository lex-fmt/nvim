-- Tree-sitter integration for Lex
-- Compiles the parser from C sources and registers it with Neovim.
-- Sources come from the tree-sitter.tar.gz release artifact (lex-fmt/tree-sitter-lex)
-- or a local dev path.

local uv = vim.loop
local M = {}

local function get_plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h")
end

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

--- Compile parser.c + scanner.c into a shared library (.so/.dylib)
--- @param src_dir string Path to directory containing parser.c and scanner.c
--- @param output_path string Path to write the compiled shared library
--- @return string|nil path Path to compiled library, or nil on error
--- @return string|nil err Error message on failure
function M.compile(src_dir, output_path)
  local cc = vim.env.CC or "cc"
  local parser_c = src_dir .. "/parser.c"
  local scanner_c = src_dir .. "/scanner.c"

  if vim.fn.filereadable(parser_c) == 0 then
    return nil, "parser.c not found at " .. parser_c
  end
  if vim.fn.filereadable(scanner_c) == 0 then
    return nil, "scanner.c not found at " .. scanner_c
  end

  -- Ensure output directory exists
  local out_dir = vim.fn.fnamemodify(output_path, ":h")
  if vim.fn.isdirectory(out_dir) == 0 then
    vim.fn.mkdir(out_dir, "p")
  end

  local sysname = uv.os_uname().sysname:lower()
  local shared_flag = "-shared"
  local extra_flags = ""
  if sysname:find("darwin") then
    extra_flags = "-undefined dynamic_lookup"
  end

  local cmd = string.format(
    "%s -o %s %s -fPIC %s -I %s %s %s",
    cc,
    vim.fn.shellescape(output_path),
    shared_flag,
    extra_flags,
    vim.fn.shellescape(src_dir),
    vim.fn.shellescape(parser_c),
    vim.fn.shellescape(scanner_c)
  )

  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "compilation failed: " .. output
  end

  return output_path
end

--- Download the tree-sitter tarball and extract source files
--- @param tag string Release tag (e.g., "v0.5.2")
--- @param dest_dir string Directory to extract into
--- @return string|nil src_dir Path to src/ directory, or nil on error
--- @return string|nil err Error message on failure
local function download_and_extract(tag, dest_dir)
  local deps = read_lex_deps()
  local repo = (deps and deps["tree-sitter-repo"]) or "lex-fmt/lex"
  local url = string.format(
    "https://github.com/%s/releases/download/%s/tree-sitter.tar.gz",
    repo, tag
  )

  local archive = dest_dir .. "/tree-sitter.tar.gz"
  local token = vim.env.LEX_GITHUB_TOKEN or vim.env.GITHUB_TOKEN
  local curl_cmd = { "curl", "-f", "-sSL", "-o", archive }
  if token and token ~= "" then
    table.insert(curl_cmd, "-H")
    table.insert(curl_cmd, "Authorization: Bearer " .. token)
  end
  table.insert(curl_cmd, url)

  local output = vim.fn.system(curl_cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "download failed: " .. output
  end

  output = vim.fn.system({ "tar", "-xzf", archive, "-C", dest_dir })
  if vim.v.shell_error ~= 0 then
    return nil, "extraction failed: " .. output
  end

  -- The tarball extracts with src/ at the root level
  local src_dir = dest_dir .. "/src"
  if vim.fn.isdirectory(src_dir) == 1 then
    return src_dir
  end

  -- Search for parser.c if not at expected location
  local paths = vim.fs.find("parser.c", { path = dest_dir, type = "file", limit = 1 })
  if paths[1] then
    return vim.fn.fnamemodify(paths[1], ":h")
  end

  return nil, "parser.c not found in tarball"
end

--- Ensure the tree-sitter parser .so is available.
--- Downloads and compiles if needed.
--- @param opts table|nil Options: { path = "local/dev/path", version = "v0.5.2" }
--- @return string|nil so_path Path to compiled .so, or nil on error
--- @return string|nil err Error message on failure
function M.ensure_parser(opts)
  opts = opts or {}
  local plugin_root = get_plugin_root()
  local bin_dir = plugin_root .. "/bin"

  -- Local dev path: compile from source tree directly
  if opts.path then
    local src_dir = opts.path .. "/src"
    local so_path = bin_dir .. "/lex-dev.so"
    return M.compile(src_dir, so_path)
  end

  -- Get pinned version
  local version = opts.version
  if not version then
    local deps = read_lex_deps()
    version = deps and deps["tree-sitter"]
  end
  if not version then
    return nil, "no tree-sitter version in lex-deps.json"
  end

  -- Check if already compiled for this version
  local so_path = bin_dir .. "/lex-" .. version .. ".so"
  if vim.fn.filereadable(so_path) == 1 then
    return so_path
  end

  -- Download, extract, compile
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")

  local src_dir, err = download_and_extract(version, tmpdir)
  if not src_dir then
    vim.fn.delete(tmpdir, "rf")
    return nil, err
  end

  local path, compile_err = M.compile(src_dir, so_path)
  vim.fn.delete(tmpdir, "rf")

  if not path then
    return nil, compile_err
  end

  return path
end

--- Setup tree-sitter for Lex buffers.
--- Registers the parser and enables highlighting + injections.
--- @param opts table|nil Options: { path = "local/dev/path", version = "v0.5.2" }
--- @return boolean success
function M.setup(opts)
  opts = opts or {}

  local so_path, err = M.ensure_parser(opts)
  if not so_path then
    vim.notify(
      "Lex tree-sitter: " .. (err or "unknown error"),
      vim.log.levels.WARN,
      { title = "Lex" }
    )
    return false
  end

  -- Register parser with Neovim
  vim.treesitter.language.add("lex", { path = so_path })

  -- Enable tree-sitter highlighting for lex buffers
  local augroup = vim.api.nvim_create_augroup("LexTreeSitter", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "lex",
    callback = function(ev)
      vim.treesitter.start(ev.buf, "lex")
    end,
  })

  -- Enable for any already-open lex buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "lex" then
      vim.treesitter.start(buf, "lex")
    end
  end

  return true
end

return M
