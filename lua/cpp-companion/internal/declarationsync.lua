local config = require("cpp-companion.internal.config")
local nodes = require("cpp-companion.internal.nodes")
local strings = require("cpp-companion.internal.strings")
local tables = require("cpp-companion.internal.tables")
local selection = require("cpp-companion.internal.selection")
local dlog = require("cpp-companion.internal.dlog")
local d = dlog.logger("cpp-companion")
local log_found_functions = false

local M = {}

local function wrap_query(query, wrapper)
  return "(" .. wrapper .. " " .. query .. ")"
end

local function debug_node_text(node, bufnr)
  if dlog.is_enabled("cpp-companion") then
    return vim.treesitter.get_node_text(node, bufnr)
  end
  return ""
end

local return_types = { "primitive_type", "qualified_identifier", "template_type", "type_identifier" }

local function_type_query = [[
  (type_qualifier)? @func_type_qualifier
  []]
    .. table.concat(
      tables.map(return_types, function(t) return strings.surround(t, "(", ")") end),
      " "
    )
    .. [[] @func_type
]]

local function function_declarator_query(wrapper)
  local query = [[
(function_declarator
  [(identifier) (field_identifier) (qualified_identifier)]? @func_name
  (parameter_list) @func_params
)
]]
  if wrapper then
    query = wrap_query(query, wrapper)
  end
  return query
end

local function declaration_query(declarator_wrapper)
  return [[
(declaration
]] .. function_type_query .. [[
]] .. function_declarator_query(declarator_wrapper) .. [[
) @func
]]
end

local function field_declaration_query(declarator_wrapper)
  return [[
(field_declaration
  (virtual)? @virtual
  (storage_class_specifier)? @storage_class
]] .. function_type_query .. [[
]] .. function_declarator_query(declarator_wrapper) .. [[
) @func
]]
end

local function definitions_query(declarator_wrapper)
  return [[
(function_definition
]] .. function_type_query .. [[
]] .. function_declarator_query(declarator_wrapper) .. [[
) @func
]]
end

local function get_lib_bufs(lib)
  local bufs = {}
  for _, h in ipairs(lib.headers) do
    d("resolved lib header file %s", h)
    if vim.fn.filereadable(h) then
      local uri = vim.uri_from_fname(h)
      table.insert(bufs, vim.uri_to_bufnr(uri))
    end
  end
  for _, s in ipairs(lib.sources) do
    d("resolved lib source file %s", s)
    if vim.fn.filereadable(s) then
      local uri = vim.uri_from_fname(s)
      table.insert(bufs, vim.uri_to_bufnr(uri))
    end
  end
  return bufs
end

local function collect_named_parents(bufnr, node, parent_type, parent_name_type)
  local result = {}
  local parent_node = node
  while true do
    parent_node = nodes.find_parent_by_type(parent_node, parent_type)
    if not parent_node then break end
    local name_node = nodes.find_child_by_type(parent_node, parent_name_type)
    assert(name_node, "Could not find name node")
    table.insert(result, 1, vim.treesitter.get_node_text(name_node, bufnr))
  end
  return result
end

local function qualifier(parts)
  local q = ""
  for _, p in ipairs(parts) do
    if #q > 0 then
      q = q .. "::"
    end
    q = q .. p
  end
  return q
end

local function fully_qualified_name(f)
  local name = ""
  local namespace = qualifier(f.namespaces)
  if #namespace > 0 then
    name = namespace
  end
  local class = qualifier(f.classes)
  if #class > 0 then
    if #name > 0 then
      name = name .. "::"
    end
    name = name .. class
  end
  if #name > 0 then
    name = name .. "::"
  end
  return name .. f.name
end

local function display_params(params)
  params = string.gsub(params, "\n+", " ")
  params = strings.unsurround(params, "(", ")")
  params = strings.trim(params)
  return strings.surround(params, "(", ")")
end

local function guess_return_value(type)
  if type == "absl::Status" then
    return "absl::OkStatus()"
  end
  return nil
end

local function definition_signature(decl)
  local signature = decl.type .. " "
  local classes = qualifier(decl.classes)
  if classes ~= "" then
    signature = signature .. classes .. "::"
  end
  signature = signature .. decl.name .. decl.params
  if decl.type_qualifier then
    signature = signature .. " " .. decl.type_qualifier
  end
  return strings.split(signature, "\n")
end

local function definition_body(decl)
  local body = definition_signature(decl)
  body[#body] = body[#body] .. " {"
  local return_value = guess_return_value(decl.type)
  local has_return = false
  if return_value then
    table.insert(body, "  return " .. return_value .. ";")
    has_return = true
  end
  table.insert(body, "}")
  return body, has_return
end

local function declaration_signature(def, decl)
  local signature = ""
  if decl.virtual then
    if #signature > 0 then
      signature = signature .. " "
    end
    signature = signature .. "virtual "
  end
  if decl.storage_class then
    if #signature > 0 then
      signature = signature .. " "
    end
    signature = signature .. decl.storage_class .. " "
  end
  signature = signature
      .. def.type
      .. " "
      .. def.name
      .. def.params
  if def.type_qualifier then
    signature = signature .. " " .. def.type_qualifier
  end
  if decl.has_semicolon then
    signature = signature .. ";"
  end
  return strings.split(signature, "\n")
end

local function function_declarator(decl)
  local signature = qualifier(decl.classes) .. "::"
      .. decl.name
      .. decl.params
  if decl.type_qualifier then
    signature = signature .. " " .. decl.type_qualifier
  end
  return strings.split(signature, "\n")
end

local function func_display(func)
  local signature = ""
  local namespaces = qualifier(func.namespaces)
  if namespaces ~= "" then
    signature = signature .. namespaces .. " "
  end
  if func.storage_class then
    signature = signature .. func.storage_class .. " "
  end
  if func.virtual then
    signature = signature .. "virtual "
  end
  signature = signature .. func.type .. " "
  local classes = qualifier(func.classes)
  if classes ~= "" then
    signature = signature .. classes .. "::"
  end
  signature = signature .. func.name .. display_params(func.params)
  if func.type_qualifier then
    signature = signature .. " " .. func.type_qualifier
  end
  return string.gsub(signature, "\n", " ")
end

local function find_unmatched_declarations(declarations, definitions)
  local declaration_map = {}
  for _, decl in ipairs(declarations) do
    declaration_map[fully_qualified_name(decl)] = decl
  end
  local definition_map = {}
  for _, def in ipairs(definitions) do
    definition_map[fully_qualified_name(def)] = def
  end
  local unmatched = {}
  for full_name, decl in pairs(declaration_map) do
    if not definition_map[full_name] then
      table.insert(unmatched, decl)
    end
  end
  return unmatched
end

local function run_query(bufnr, node, query_str, opts)
  d("running query %s", query_str)
  opts = opts or {}
  local query = vim.treesitter.query.parse("cpp", query_str)
  local func
  local functions = {}
  local func_type_qualifier = nil
  for id, n in query:iter_captures(node, bufnr) do
    if query.captures[id] == "func" then
      func = {
        bufnr = bufnr,
        node = n,
        classes = collect_named_parents(bufnr, n, "class_specifier", "type_identifier"),
        namespaces = collect_named_parents(bufnr, n, "namespace_definition", "namespace_identifier"),
        has_semicolon = string.sub(vim.treesitter.get_node_text(n, bufnr), -1) == ";",
      }
      table.insert(functions, func)
      func_type_qualifier = nil
    elseif query.captures[id] == "virtual" then
      func.virtual = true
    elseif query.captures[id] == "storage_class" then
      func.storage_class = vim.treesitter.get_node_text(n, bufnr)
    elseif query.captures[id] == "func_type_qualifier" then
      func.ret_type_qualifier = vim.treesitter.get_node_text(n, bufnr)
    elseif query.captures[id] == "func_type" then
      func.type = vim.treesitter.get_node_text(n, bufnr)
      if func_type_qualifier then
        func.type = func_type_qualifier .. " " .. func.type
      end
      if opts.ret_type_reference then
        func.type = func.type .. "&"
      end
      if opts.ret_type_pointer then
        func.type = func.type .. "*"
      end
    elseif query.captures[id] == "func_name" then
      local name = vim.treesitter.get_node_text(n, bufnr)
      if not string.find(name, "::") then
        func.name = name
      else
        -- Otherwise, this is a qualified name in the definition.
        local parts = vim.split(name, "::")
        func.classes = {}
        for i = 1, #parts - 1 do
          table.insert(func.classes, parts[i])
        end
        func.name = parts[#parts]
      end
    elseif query.captures[id] == "func_params" then
      func.params = vim.treesitter.get_node_text(n, bufnr)
      local type_node = nodes.get_next_node(n)
      if type_node then
        func.type_qualifier = vim.treesitter.get_node_text(type_node, bufnr)
      end
    end
  end
  d("found %d functions", #functions)
  if log_found_functions then
    for i, f in ipairs(functions) do
      d("%d: %s", i, func_display(f))
    end
  end
  return functions
end

local function node_get_definitions(bufnr, node)
  return tables.merge_arrays(
    run_query(bufnr, node, definitions_query()),
    run_query(bufnr, node, definitions_query("reference_declarator"),
      { ret_type_reference = true }),
    run_query(bufnr, node, definitions_query("pointer_declarator"),
      { ret_type_pointer = true }))
end

local function node_get_declarations(bufnr, node)
  return tables.merge_arrays(
    run_query(bufnr, node, field_declaration_query()),
    run_query(bufnr, node, field_declaration_query("reference_declarator"),
      { ret_type_reference = true }),
    run_query(bufnr, node, field_declaration_query("pointer_declarator"),
      { ret_type_pointer = true }),
    run_query(bufnr, node, declaration_query()),
    run_query(bufnr, node, declaration_query("reference_declarator"),
      { ret_type_reference = true }),
    run_query(bufnr, node, declaration_query("pointer_declarator"),
      { ret_type_pointer = true }))
end

local function is_same_qualified_id(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

local function compare_qualified_id(a, b)
  for i = 1, #a do
    if i > #b then
      return 1
    end
    if a[i] < b[i] then
      return -1
    end
    if b[i] > a[i] then
      return 1
    end
  end
  return 0
end

local function full_name_matches(a, b)
  return is_same_qualified_id(a.namespaces, b.namespaces)
      and is_same_qualified_id(a.classes, b.classes)
      and a.name == b.name
end

local function sort_functions(functions, ref_func)
  table.sort(functions, function(a, b)
    if ref_func then
      local a_full_match = full_name_matches(a, ref_func)
      local b_full_match = full_name_matches(b, ref_func)
      if a_full_match and not b_full_match then
        return true
      end
      if not a_full_match and b_full_match then
        return false
      end
    end
    local namespace_cmp = compare_qualified_id(a.namespaces, b.namespaces)
    if namespace_cmp < 0 then
      return true
    end
    if namespace_cmp > 0 then
      return false
    end
    local class_cmp = compare_qualified_id(a.classes, b.classes)
    if class_cmp < 0 then
      return true
    end
    if class_cmp > 0 then
      return false
    end
    return a.name < b.name
  end)
end

local function is_only_match(sorted_funcs, f)
  if #sorted_funcs == 0 then
    return false
  end
  local only_match = full_name_matches(sorted_funcs[1], f)
  if only_match and #sorted_funcs > 1 then
    only_match = not full_name_matches(sorted_funcs[2], f)
  end
  return only_match
end

local function buf_get_declarations(bufnr)
  bufnr = bufnr or 0
  local parser = vim.treesitter.get_parser(bufnr, "cpp")
  local tree = parser:parse()
  local root = tree[1]:root()
  return node_get_declarations(bufnr, root)
end

local function buf_get_definitions(bufnr)
  bufnr = bufnr or 0
  local parser = vim.treesitter.get_parser(bufnr, "cpp")
  local tree = parser:parse()
  local root = tree[1]:root()
  return node_get_definitions(bufnr, root)
end

local function update_declaration_node(decl, def)
  nodes.update_node_text(decl.bufnr, decl.node, declaration_signature(def, decl))
  vim.notify("Updated declaration " .. fully_qualified_name(def))
end

local function update_definition_node(def, decl)
  local type_node = nodes.find_child_by_one_of_types(def.node, return_types)
  if type_node then
    d("updating type node %s with %s", debug_node_text(type_node, def.bufnr), decl.type)
    nodes.update_node_text(def.bufnr, type_node, { decl.type .. " " })
  end
  local declarator_node = nodes.find_child_by_one_of_types(def.node,
    { "function_declarator", "reference_declarator", "pointer_declarator" })
  if declarator_node then
    d("updating declarator node %s", debug_node_text(declarator_node, def.bufnr))
    nodes.update_node_text(def.bufnr, declarator_node, function_declarator(decl))
    vim.notify("Updated definition " .. fully_qualified_name(decl))
  else
    vim.notify("Could not find definition " .. fully_qualified_name(decl), vim.log.levels.ERROR)
  end
end

function M.sibling_dot_h_header_locator(bufnr)
  bufnr = bufnr or 0
  local filename = vim.api.nvim_buf_get_name(bufnr)
  return vim.fn.fnamemodify(filename, ":r") .. ".h"
end

function M.get_declarations(bufnr)
  bufnr = bufnr or 0
  local declarations = {}
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local lib = config.get().lib_resolver(file_path)
  local bufs = get_lib_bufs(lib)
  for _, b in ipairs(bufs) do
    declarations = tables.merge_arrays(declarations, buf_get_declarations(b))
  end
  return declarations
end

function M.insert_definition()
  local declarations = M.get_declarations(0)
  local function insert_signature(decl)
    local body, has_return = definition_body(decl)
    vim.api.nvim_put(body, "c", false, false)
    local pos = vim.api.nvim_win_get_cursor(0)
    local lines_from_bottom = 2 -- } and line above
    if has_return then
      lines_from_bottom = 3 -- }, return statement and line above
    end
    pos[1] = pos[1] + #body - lines_from_bottom
    vim.api.nvim_win_set_cursor(0, pos)
    vim.cmd("norm! o")
    -- TODO: Find better way to indent.
    vim.api.nvim_put({ "  " }, "c", false, true)
  end
  local definitions = M.get_definitions()
  local unmatched = find_unmatched_declarations(declarations, definitions)
  if #unmatched == 1 then
    insert_signature(unmatched[1])
    return
  end
  selection.select({
    prompt = "Select function declaration",
    values = declarations,
    entry_func = function(decl)
      local signature = func_display(decl)
      local start_line = decl.node:start()
      return {
        value = signature,
        ordinal = signature,
        display = signature,
        filename = vim.api.nvim_buf_get_name(decl.bufnr),
        lnum = start_line + 1,
        decl = decl,
      }
    end,
    on_selected = function(entry)
      insert_signature(entry.decl)
    end,
  })
end

function M.definition_at_cursor()
  local node = nodes.get_node_at_cursor()
  local func = nodes.find_parent_by_type(node, "function_definition")
  if func then
    local definitions = node_get_definitions(0, func)
    if #definitions == 1 then
      return definitions[1]
    end
  end
  return nil
end

function M.declaration_at_cursor()
  local node = nodes.get_node_at_cursor()
  local field_node = nodes.find_parent_by_type(node, "field_declaration")
  if field_node then
    local declarations = node_get_declarations(0, field_node)
    if #declarations == 1 then
      return declarations[1]
    end
  end
  local declaration_node = nodes.find_parent_by_type(node, "declaration")
  if declaration_node then
    local declarations = node_get_declarations(0, declaration_node)
    if #declarations == 1 then
      return declarations[1]
    end
  end
  return nil
end

function M.get_definitions(bufnr)
  bufnr = bufnr or 0
  local definitions = {}
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local lib = config.get().lib_resolver(file_path)
  local bufs = get_lib_bufs(lib)
  for _, b in ipairs(bufs) do
    definitions = tables.merge_arrays(definitions, buf_get_definitions(b))
  end
  return definitions
end

function M.update_declaration(definition)
  local declarations = M.get_declarations()
  sort_functions(declarations, definition)
  if is_only_match(declarations, definition) then
    update_declaration_node(declarations[1], definition)
    return
  end
  selection.select({
    prompt = "Select declaration to update",
    values = selection.to_ordinal_pairs(declarations),
    entry_func = function(pair)
      local decl = pair.item
      local signature = func_display(decl)
      local start_line = decl.node:start()
      return {
        value = signature,
        ordinal = pair.ordinal,
        display = signature,
        filename = vim.api.nvim_buf_get_name(decl.bufnr),
        lnum = start_line + 1,
        decl = decl,
      }
    end,
    on_selected = function(entry)
      update_declaration_node(entry.decl, definition)
    end,
  })
end

function M.update_definition(decl)
  local definitions = M.get_definitions()
  sort_functions(definitions, decl)
  if is_only_match(definitions, decl) then
    update_definition_node(definitions[1], decl)
    return
  end
  selection.select({
    prompt = "Select definition to update",
    values = selection.to_ordinal_pairs(definitions),
    entry_func = function(pair)
      local def = pair.item
      local signature = func_display(def)
      local start_line = def.node:start()
      return {
        value = signature,
        ordinal = pair.ordinal,
        display = signature,
        filename = vim.api.nvim_buf_get_name(def.bufnr),
        lnum = start_line + 1,
        def = def,
      }
    end,
    on_selected = function(entry)
      update_definition_node(entry.def, decl)
    end,
  })
end

function M.sync_declaration_and_definition()
  local definition = M.definition_at_cursor()
  if definition then
    M.update_declaration(definition)
    return
  end
  local declaration = M.declaration_at_cursor()
  if declaration then
    M.update_definition(declaration)
    return
  end
  vim.notify("Could not find a single function definition or declaration at the cursor position", vim.log.levels.INFO)
end

return M
