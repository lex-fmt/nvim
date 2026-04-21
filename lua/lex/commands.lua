-- Lex Neovim Plugin - Commands
-- ==============================
--
-- LSP-driven commands for annotation navigation, editing, and export/import.

local M = {}

-- Get the lexd-lsp client for the current buffer
local function get_lex_client()
  local clients = vim.lsp.get_clients({ name = "lex_lsp", bufnr = 0 })
  return clients[1]
end

-- Get current cursor position in LSP format (0-indexed)
local function get_cursor_position()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return {
    line = cursor[1] - 1,
    character = cursor[2],
  }
end

-- Execute an LSP command and return the result
local function execute_lsp_command(command, arguments)
  local client = get_lex_client()
  if not client then
    vim.notify("Lex LSP not attached", vim.log.levels.WARN)
    return nil
  end

  local result = client.request_sync("workspace/executeCommand", {
    command = command,
    arguments = arguments,
  }, 5000, 0)

  if result and result.result then
    return result.result
  end
  return nil
end

-- Navigate to an annotation (next or previous)
local function navigate_annotation(direction)
  local uri = vim.uri_from_bufnr(0)
  local position = get_cursor_position()

  local command = direction == "next" and "lex.next_annotation" or "lex.previous_annotation"
  local location = execute_lsp_command(command, { uri, position })

  if not location then
    vim.notify("No " .. direction .. " annotation found", vim.log.levels.INFO)
    return
  end

  -- Jump to the location
  local target_uri = location.uri
  local target_range = location.range

  -- Open the file if it's different
  if target_uri ~= uri then
    vim.cmd("edit " .. vim.uri_to_fname(target_uri))
  end

  -- Move cursor to the start of the annotation (1-indexed)
  local target_line = target_range.start.line + 1
  local target_col = target_range.start.character
  vim.api.nvim_win_set_cursor(0, { target_line, target_col })
  vim.cmd("normal! zz") -- Center the view
end

function M.next_annotation()
  navigate_annotation("next")
end

function M.previous_annotation()
  navigate_annotation("previous")
end

-- Apply a workspace edit from LSP (used by resolve/toggle annotations)
local function apply_workspace_edit(edit)
  if not edit then
    return false
  end

  local client = get_lex_client()
  if not client then
    return false
  end

  -- Convert LSP workspace edit to Neovim format and apply
  vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding or "utf-16")
  return true
end

function M.resolve_annotation()
  local uri = vim.uri_from_bufnr(0)
  local position = get_cursor_position()

  local edit = execute_lsp_command("lex.resolve_annotation", { uri, position })

  if not edit then
    vim.notify("No annotation at cursor position", vim.log.levels.INFO)
    return
  end

  if apply_workspace_edit(edit) then
    vim.notify("Annotation resolved", vim.log.levels.INFO)
  else
    vim.notify("Failed to apply edit", vim.log.levels.ERROR)
  end
end

function M.toggle_annotations()
  local uri = vim.uri_from_bufnr(0)
  local position = get_cursor_position()

  local edit = execute_lsp_command("lex.toggle_annotations", { uri, position })

  if not edit then
    vim.notify("No annotation at cursor position", vim.log.levels.INFO)
    return
  end

  if apply_workspace_edit(edit) then
    vim.notify("Annotation toggled", vim.log.levels.INFO)
  else
    vim.notify("Failed to apply edit", vim.log.levels.ERROR)
  end
end

-- File picker with Telescope fallback to vim.ui.input
local function pick_file(opts, callback)
  opts = opts or {}
  local prompt = opts.prompt or "Select file: "

  local has_telescope, telescope = pcall(require, "telescope.builtin")
  if has_telescope then
    telescope.find_files({
      prompt_title = prompt,
      attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            callback(selection.path or selection[1])
          end
        end)
        return true
      end,
    })
  else
    vim.ui.input({ prompt = prompt, completion = "file" }, function(path)
      if path and path ~= "" then
        callback(path)
      end
    end)
  end
end

-- Insert snippet payload from LSP at cursor
local function insert_snippet_payload(payload)
  if not payload or not payload.text then
    vim.notify("Invalid snippet payload", vim.log.levels.ERROR)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  -- Insert newline before if not at start of document
  local prefix = ""
  if line > 1 or col > 0 then
    prefix = "\n"
  end
  local suffix = "\n"
  local text = prefix .. payload.text .. suffix

  -- Insert the text
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(0, line - 1, col, line - 1, col, lines)

  -- Move cursor to the position indicated by cursorOffset
  local offset = #prefix + payload.cursorOffset
  local new_line = line
  local new_col = col
  local chars_counted = 0

  for i, l in ipairs(lines) do
    if chars_counted + #l + 1 > offset then
      new_line = line + i - 1
      new_col = offset - chars_counted
      break
    end
    chars_counted = chars_counted + #l + 1
  end

  vim.api.nvim_win_set_cursor(0, { new_line, new_col })
end

function M.insert_asset()
  pick_file({ prompt = "Select asset to insert" }, function(path)
    local uri = vim.uri_from_bufnr(0)
    local position = get_cursor_position()

    local payload = execute_lsp_command("lex.insert_asset", { uri, position, path })
    if payload then
      insert_snippet_payload(payload)
    else
      vim.notify("Failed to generate asset reference", vim.log.levels.ERROR)
    end
  end)
end

function M.insert_verbatim()
  pick_file({ prompt = "Select file to embed" }, function(path)
    local uri = vim.uri_from_bufnr(0)
    local position = get_cursor_position()

    local payload = execute_lsp_command("lex.insert_verbatim", { uri, position, path })
    if payload then
      insert_snippet_payload(payload)
    else
      vim.notify("Failed to generate verbatim block", vim.log.levels.ERROR)
    end
  end)
end

-- Get default export path (same dir, new extension)
local function get_default_export_path(format)
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == "" then
    return nil
  end

  local ext = format == "markdown" and ".md" or ("." .. format)
  local base = buf_name:gsub("%.lex$", "")
  return base .. ext
end

-- Export current buffer to specified format via LSP
local function export_to_format(format, output_path)
  local client = get_lex_client()
  if not client then
    vim.notify("Lex LSP not attached", vim.log.levels.WARN)
    return
  end

  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == "" then
    vim.notify("Save the buffer first", vim.log.levels.ERROR)
    return
  end

  local target_path = output_path or get_default_export_path(format)
  if not target_path then
    vim.notify("Could not determine output path", vim.log.levels.ERROR)
    return
  end

  -- Get buffer content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Build arguments: [format, content, sourceUri, outputPath]
  local uri = vim.uri_from_bufnr(0)
  local result = execute_lsp_command("lex.export", { format, content, uri, target_path })

  if not result then
    vim.notify("Export failed", vim.log.levels.ERROR)
    return
  end

  -- For text formats (markdown, html), LSP returns the content as string
  -- For binary formats (pdf), LSP writes to outputPath and returns the path
  if format == "pdf" then
    vim.notify("Exported to " .. target_path, vim.log.levels.INFO)
  else
    -- Write the returned content to target file
    local file = io.open(target_path, "w")
    if file then
      file:write(result)
      file:close()
      vim.notify("Exported to " .. target_path, vim.log.levels.INFO)
    else
      vim.notify("Failed to write output file", vim.log.levels.ERROR)
    end
  end
end

function M.export_markdown(opts)
  opts = opts or {}
  export_to_format("markdown", opts.fargs and opts.fargs[1])
end

function M.export_html(opts)
  opts = opts or {}
  export_to_format("html", opts.fargs and opts.fargs[1])
end

function M.export_pdf(opts)
  opts = opts or {}
  export_to_format("pdf", opts.fargs and opts.fargs[1])
end

-- Supported filetypes for conversion to Lex
local convertible_filetypes = {
  markdown = "markdown",
}

function M.convert_to_lex()
  local client = get_lex_client()
  if not client then
    vim.notify("Lex LSP not attached", vim.log.levels.WARN)
    return
  end

  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == "" then
    vim.notify("Save the buffer first", vim.log.levels.ERROR)
    return
  end

  local format = convertible_filetypes[vim.bo.filetype]
  if not format then
    local supported = table.concat(vim.tbl_keys(convertible_filetypes), ", ")
    vim.notify("Convert to Lex is available for: " .. supported, vim.log.levels.ERROR)
    return
  end

  -- Get buffer content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Call LSP import command: [format, content]
  local result = execute_lsp_command("lex.import", { format, content })

  if not result then
    vim.notify("Convert to Lex failed", vim.log.levels.ERROR)
    return
  end

  -- Write to .lex file and open it
  local target_path = buf_name:gsub("%.[^.]+$", "") .. ".lex"
  local file = io.open(target_path, "w")
  if file then
    file:write(result)
    file:close()
    vim.cmd("edit " .. target_path)
    vim.notify("Converted to " .. target_path, vim.log.levels.INFO)
  else
    vim.notify("Failed to write output file", vim.log.levels.ERROR)
  end
end

-- Reorder numbered footnote references + definitions so they're sequential
-- starting at 1, in order of appearance. Server-side implementation in
-- `lex.footnotes.reorder` (lex-lsp); this function just posts the buffer and
-- applies the returned text as a whole-document replacement.
function M.reorder_footnotes()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "lex" then
    vim.notify("Reorder Footnotes is only available for .lex files", vim.log.levels.WARN)
    return
  end

  local original_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local original = table.concat(original_lines, "\n")
  local result = execute_lsp_command("lex.footnotes.reorder", { original })

  if type(result) ~= "string" or result == original then
    return
  end

  local new_lines = vim.split(result, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
end

-- Format the table at cursor via LSP
function M.format_table()
  local client = get_lex_client()
  if not client then
    vim.notify("Lex LSP not attached", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")
  local position = get_cursor_position()

  local result = execute_lsp_command("lex.table.format", { content, position.line, position.character })

  if not result then
    vim.notify("No table found at cursor position", vim.log.levels.INFO)
    return
  end

  -- result is { start, end, newText } with byte offsets
  local start_byte = result.start
  local end_byte = result["end"]
  local new_text = result.newText

  -- Convert byte offsets to line/col positions
  local byte_count = 0
  local start_line, start_col, end_line, end_col
  for i, line in ipairs(lines) do
    local line_len = #line + 1 -- +1 for newline
    if not start_line and byte_count + line_len > start_byte then
      start_line = i - 1
      start_col = start_byte - byte_count
    end
    if not end_line and byte_count + line_len > end_byte then
      end_line = i - 1
      end_col = end_byte - byte_count
    end
    byte_count = byte_count + line_len
    if start_line and end_line then break end
  end
  -- Handle end at exact end of content
  if not end_line then
    end_line = #lines - 1
    end_col = #lines[#lines]
  end

  local new_lines = vim.split(new_text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(0, start_line, start_col, end_line, end_col, new_lines)
  vim.notify("Table formatted", vim.log.levels.INFO)
end

-- Navigate between pipe-delimited table cells.
--
-- All the pipe-position math lives server-side in lex-lsp (`lex.table.next_cell`
-- and `lex.table.previous_cell`) since v0.8.3, so this function is primarily
-- a forwarder. The LSP returns `{ inTable, position? }`:
--
--   - `inTable = false` → cursor is not on a pipe row; emit the editor's
--     default Tab / outdent so structural indent/dedent still works.
--   - `inTable = true` with `position` → move the cursor there.
--   - `inTable = true` without `position` → on a pipe row but no valid
--     move (table edge, malformed row): no-op.
--
-- Two short-circuits before the LSP call: (1) if the current line is not
-- a pipe row we fall through locally instead of paying a round-trip per
-- keystroke; (2) if no `lex_lsp` client is attached to this buffer we
-- also fall through silently — otherwise `execute_lsp_command` would
-- emit a "Lex LSP not attached" warning on every Tab.
function M.navigate_table_cell(direction)
  local command = direction == "next" and "lex.table.next_cell" or "lex.table.previous_cell"
  local fallthrough_key = direction == "next" and "<C-t>" or "<C-d>"

  local function fallthrough()
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(fallthrough_key, true, false, true),
      "n",
      false
    )
  end

  -- Fast path: not on a pipe row → no LSP call needed.
  if not vim.api.nvim_get_current_line():match("^%s*|") then
    fallthrough()
    return
  end

  -- Silent fall-through when the LSP is unavailable. Checking the client
  -- up-front also bypasses the warning that execute_lsp_command would
  -- otherwise emit on every Tab.
  if not get_lex_client() then
    fallthrough()
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1 -- LSP expects 0-indexed line
  local col = cursor[2]
  local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

  local outcome = execute_lsp_command(command, { content, line, col })
  if not outcome or not outcome.inTable then
    fallthrough()
    return
  end

  if not outcome.position then
    return
  end

  vim.api.nvim_win_set_cursor(0, { outcome.position.line + 1, outcome.position.column })
end

-- Setup all user commands
function M.setup()
  -- Navigation commands
  vim.api.nvim_create_user_command("LexNextAnnotation", M.next_annotation, {
    desc = "Jump to next annotation",
  })
  vim.api.nvim_create_user_command("LexPrevAnnotation", M.previous_annotation, {
    desc = "Jump to previous annotation",
  })

  -- Editing commands
  vim.api.nvim_create_user_command("LexResolveAnnotation", M.resolve_annotation, {
    desc = "Resolve annotation at cursor",
  })
  vim.api.nvim_create_user_command("LexToggleAnnotations", M.toggle_annotations, {
    desc = "Toggle annotation resolution status",
  })
  vim.api.nvim_create_user_command("LexInsertAsset", M.insert_asset, {
    desc = "Insert asset reference at cursor",
  })
  vim.api.nvim_create_user_command("LexInsertVerbatim", M.insert_verbatim, {
    desc = "Insert verbatim block from file",
  })

  -- Export/Import commands
  vim.api.nvim_create_user_command("LexExportMarkdown", M.export_markdown, {
    nargs = "?",
    complete = "file",
    desc = "Export to Markdown",
  })
  vim.api.nvim_create_user_command("LexExportHtml", M.export_html, {
    nargs = "?",
    complete = "file",
    desc = "Export to HTML",
  })
  vim.api.nvim_create_user_command("LexExportPdf", M.export_pdf, {
    nargs = "?",
    complete = "file",
    desc = "Export to PDF",
  })
  vim.api.nvim_create_user_command("LexConvertToLex", M.convert_to_lex, {
    desc = "Convert current buffer (Markdown) to Lex",
  })

  -- Table commands
  vim.api.nvim_create_user_command("LexReorderFootnotes", M.reorder_footnotes, {
    desc = "Reorder numbered footnotes to be sequential",
  })
  vim.api.nvim_create_user_command("LexFormatTable", M.format_table, {
    desc = "Format table at cursor",
  })
end

-- Setup default keymaps for .lex files
function M.setup_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true }

  -- Annotation navigation (]a and [a are conventional next/prev mappings)
  vim.keymap.set("n", "]a", M.next_annotation, vim.tbl_extend("force", opts, { desc = "Next annotation" }))
  vim.keymap.set("n", "[a", M.previous_annotation, vim.tbl_extend("force", opts, { desc = "Previous annotation" }))

  -- Table cell navigation (Tab/Shift-Tab in insert mode)
  vim.keymap.set("i", "<Tab>", function() M.navigate_table_cell("next") end, vim.tbl_extend("force", opts, { desc = "Next table cell" }))
  vim.keymap.set("i", "<S-Tab>", function() M.navigate_table_cell("previous") end, vim.tbl_extend("force", opts, { desc = "Previous table cell" }))

  -- Format table at cursor
  vim.keymap.set("n", "<leader>tf", M.format_table, vim.tbl_extend("force", opts, { desc = "Format table" }))
end

return M
