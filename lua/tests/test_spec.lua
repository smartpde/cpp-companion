local declarationsync = require("cpp-companion.internal.declarationsync")
local tables = require("cpp-companion.internal.tables")
local strings = require("cpp-companion.internal.strings")

local function make_code_buf(code_lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "cpp"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, code_lines)
  return buf
end

local function check_declarations(code, declarations)
  local buf = make_code_buf(vim.split(code, "\n"))
  local actual = declarationsync.get_declarations(buf)
  local actual_funcs = tables.map(actual, function(d)
    return declarationsync.func_display(d)
  end)
  assert.are.same(actual_funcs, declarations)
end

local function check_definitions(code, definitions)
  local buf = make_code_buf(vim.split(code, "\n"))
  local actual = declarationsync.get_definitions(buf)
  local actual_funcs = tables.map(actual, function(d)
    return declarationsync.func_display(d)
  end)
  assert.are.same(actual_funcs, definitions)
end

local function trim_lines(lines)
  for i, l in ipairs(lines) do
    lines[i] = strings.trim(l)
  end
  return table.concat(lines, "\n")
end

local function trim_text(text)
  local lines = vim.split(text, "\n")
  return trim_lines(lines)
end

local function check_sync(code, expected_code)
  local lines = vim.split(code, "\n")
  local row, col
  for i, l in ipairs(lines) do
    local c = string.find(l, "%^")
    if c then
      row = i
      col = c
      lines[i] = string.gsub(l, "%^", "")
      break
    end
  end
  local buf = make_code_buf(lines)
  local win = vim.api.nvim_open_win(buf, false, { height = 100, width = 100, relative = "editor", row = 1, col = 1 })
  vim.api.nvim_win_set_cursor(win, { row, col - 1 })
  declarationsync.sync_declaration_and_definition(win)
  local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert.are.same(trim_lines(new_lines), trim_text(expected_code))
end


describe("declarationsync", function()
  describe("finds declarations", function()
    it("test", function()
    end)
  end)
end)
