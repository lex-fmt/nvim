-- Test: Table cell navigation (Tab/Shift-Tab between pipe cells)
--
-- Verifies that:
-- 1. navigate_table_cell("next") moves to the next cell in the same row
-- 2. navigate_table_cell("next") wraps to first cell of next row
-- 3. navigate_table_cell("previous") moves to the previous cell
-- 4. navigate_table_cell("previous") wraps to last cell of previous row

local script_path = debug.getinfo(1).source:sub(2)
local test_dir = vim.fn.fnamemodify(script_path, ":p:h")
local plugin_dir = vim.fn.fnamemodify(test_dir, ":h")
vim.opt.rtp:prepend(plugin_dir)

-- Load the commands module
local ok, commands = pcall(require, "lex.commands")
if not ok then
  print("TEST_FAILED: Could not load lex.commands: " .. tostring(commands))
  vim.cmd("cquit 1")
end

-- Create a buffer with table content
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)

local table_content = {
  "    | Name  | Score |",
  "    | Alpha | 100   |",
  "    | Beta  | 200   |",
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, table_content)

-- Compute expected pipe positions for "    | Name  | Score |"
-- Pipes at byte offsets: 4, 12, 20 (0-indexed)
-- Cell content starts at pipe + 2

-- Test 1: Navigate next from first cell to second cell
-- Position cursor at "Name" (col 6 = after "| " inside first cell)
vim.api.nvim_win_set_cursor(0, { 1, 6 })
commands.navigate_table_cell("next")
local cursor = vim.api.nvim_win_get_cursor(0)
-- Second pipe at col 12, target is 12 + 2 = 14
if cursor[1] ~= 1 or cursor[2] ~= 14 then
  print(string.format("TEST_FAILED: Expected (1, 14), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end

print("TEST_PASSED: next cell moves to second cell in same row")

-- Test 2: Navigate next from last cell wraps to next row
-- Position cursor at "Score" in first row (col 14)
vim.api.nvim_win_set_cursor(0, { 1, 14 })
commands.navigate_table_cell("next")
cursor = vim.api.nvim_win_get_cursor(0)
-- Should wrap to first cell of row 2: first pipe at col 4, target col 6
if cursor[1] ~= 2 or cursor[2] ~= 6 then
  print(string.format("TEST_FAILED: Expected (2, 6), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end

print("TEST_PASSED: next cell wraps to first cell of next row")

-- Test 3: Navigate previous from second cell to first cell
-- Position cursor at "100" in second row (col 14)
vim.api.nvim_win_set_cursor(0, { 2, 14 })
commands.navigate_table_cell("previous")
cursor = vim.api.nvim_win_get_cursor(0)
-- Should be in "Alpha" cell: first pipe at col 4, target col 6
if cursor[1] ~= 2 or cursor[2] ~= 6 then
  print(string.format("TEST_FAILED: Expected (2, 6), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end

print("TEST_PASSED: previous cell moves to first cell in same row")

-- Test 4: Navigate previous from first cell wraps to previous row
-- Position cursor at "Alpha" in second row (col 6)
vim.api.nvim_win_set_cursor(0, { 2, 6 })
commands.navigate_table_cell("previous")
cursor = vim.api.nvim_win_get_cursor(0)
-- Should wrap to last cell of row 1: second-to-last pipe at col 12, target col 14
if cursor[1] ~= 1 or cursor[2] ~= 14 then
  print(string.format("TEST_FAILED: Expected (1, 14), got (%d, %d)", cursor[1], cursor[2]))
  vim.cmd("cquit 1")
end

print("TEST_PASSED: previous cell wraps to last cell of previous row")

print("TEST_PASSED: All table navigation tests passed")
vim.cmd("qall!")
