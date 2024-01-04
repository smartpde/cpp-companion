local strings = require("cpp-companion.internal.strings")
local parsers = require("nvim-treesitter.parsers")
local M = {}

function M.find_children_by_type(node, child_type, bufnr)
  bufnr = bufnr or 0
  local result = {}
  for i = 0, node:child_count() - 1 do
    local child = node:child(i)
    if child:type() == child_type then
      table.insert(result, child)
    end
  end
  return result
end

function M.find_child_by_type(node, child_type)
  for i = 0, node:child_count() - 1 do
    local child = node:child(i)
    if child:type() == child_type then
      return child
    end
    local res = M.find_child_by_type(child, child_type)
    if res then
      return res
    end
  end
  return nil
end

function M.find_child_by_one_of_types(node, child_types)
  for _, type in ipairs(child_types) do
    local child = M.find_child_by_type(node, type)
    if child then
      return child
    end
  end
  return nil
end

function M.find_parent_by_type(node, parent_type)
  local parent = node:parent()
  while parent and parent:type() ~= parent_type do
    parent = parent:parent()
  end
  return parent
end

function M.get_single_child_by_field(node, field)
  local children = node:field(field)
  if #children == 0 then
    return nil
  end
  assert(#children == 1, "Expected a single key in node " .. node:type() ..
  ", but found " .. #children)
  return children[1]
end

function M.find_in_string_list(node, needle, bufnr)
  bufnr = bufnr or 0
  assert(node:type() == "list", node:type())
  local values = M.find_children_by_type(node, "string")
  for _, value in ipairs(values) do
    local v = vim.treesitter.query.get_node_text(value, bufnr)
    if strings.unquote(v) == needle then
      return true
    end
  end
  return false
end

function M.update_node_text(bufnr, node, new_text_lines)
  local start_row, start_col = node:start()
  local end_row, end_col = node:end_()
  vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col,
    new_text_lines)
end

-- Get next node with same parent
---@param node                  TSNode
---@param allow_switch_parents? boolean allow switching parents if last node
---@param allow_next_parent?    boolean allow next parent if last node and next parent without children
function M.get_next_node(node, allow_switch_parents, allow_next_parent)
  local destination_node ---@type TSNode
  local parent = node:parent()

  if not parent then
    return
  end
  local found_pos = 0
  for i = 0, parent:named_child_count() - 1, 1 do
    if parent:named_child(i) == node then
      found_pos = i
      break
    end
  end
  if parent:named_child_count() > found_pos + 1 then
    destination_node = parent:named_child(found_pos + 1)
  elseif allow_switch_parents then
    local next_node = M.get_next_node(node:parent())
    if next_node and next_node:named_child_count() > 0 then
      destination_node = next_node:named_child(0)
    elseif next_node and allow_next_parent then
      destination_node = next_node
    end
  end

  return destination_node
end

function M.get_root_for_position(line, col, root_lang_tree)
  if not root_lang_tree then
    if not parsers.has_parser() then
      return
    end

    root_lang_tree = parsers.get_parser()
  end

  local lang_tree = root_lang_tree:language_for_range { line, col, line, col }

  for _, tree in ipairs(lang_tree:trees()) do
    local root = tree:root()

    if root and vim.treesitter.is_in_node_range(root, line, col) then
      return root, tree, lang_tree
    end
  end

  -- This isn't a likely scenario, since the position must belong to a tree somewhere.
  return nil, nil, lang_tree
end

function M.get_node_at_cursor(winnr, ignore_injected_langs)
  winnr = winnr or 0
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local cursor_range = { cursor[1] - 1, cursor[2] }

  local buf = vim.api.nvim_win_get_buf(winnr)
  local root_lang_tree = parsers.get_parser(buf)
  if not root_lang_tree then
    return
  end

  local root ---@type TSNode|nil
  if ignore_injected_langs then
    for _, tree in ipairs(root_lang_tree:trees()) do
      local tree_root = tree:root()
      if tree_root and vim.treesitter.is_in_node_range(tree_root, cursor_range[1], cursor_range[2]) then
        root = tree_root
        break
      end
    end
  else
    root = M.get_root_for_position(cursor_range[1], cursor_range[2], root_lang_tree)
  end

  if not root then
    return
  end

  return root:named_descendant_for_range(cursor_range[1], cursor_range[2], cursor_range[1], cursor_range[2])
end

return M
