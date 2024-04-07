local config = require("cpp-companion.internal.config")
local nodes = require("cpp-companion.internal.nodes")
local strings = require("cpp-companion.internal.strings")
local tables = require("cpp-companion.internal.tables")
local selection = require("cpp-companion.internal.selection")
local dlog = require("cpp-companion.internal.dlog")
local d = dlog.logger("cpp-companion")

local M = {}

local function debug_node_text(node, buf)
  if dlog.is_enabled("cpp-companion") then
    return vim.treesitter.get_node_text(node, buf)
  end
  return ""
end

local possible_return_types = { "primitive_type", "qualified_identifier",
  "template_type", "type_identifier" }
local possible_declarators = { "ERROR", "pointer_declarator",
  "reference_declarator", "function_declarator" }
local possible_types = { "primitive_type", "type_identifier", "qualified_identifier" }

local function get_lib_bufs(buf)
  local bufs = {}
  table.insert(bufs, buf)
  local file_path = vim.api.nvim_buf_get_name(buf)
  if not file_path or file_path == "" then
    -- file not saved yet
    return bufs
  end
  file_path = vim.fs.normalize(file_path)
  local lib = config.get().lib_resolver(file_path)
  for _, h in ipairs(lib.headers) do
    h = vim.fs.normalize(h)
    if h ~= file_path then
      d("resolved lib header file %s", h)
      if vim.fn.filereadable(h) then
        local uri = vim.uri_from_fname(h)
        table.insert(bufs, vim.uri_to_bufnr(uri))
      end
    end
  end
  for _, s in ipairs(lib.sources) do
    s = vim.fs.normalize(s)
    if s ~= file_path then
      d("resolved lib source file %s", s)
      if vim.fn.filereadable(s) then
        local uri = vim.uri_from_fname(s)
        table.insert(bufs, vim.uri_to_bufnr(uri))
      end
    end
  end
  return bufs
end

local function collect_named_parents(buf, node, parent_specs)
  local result = {}
  node = node:parent()
  while true do
    if not node then
      break
    end
    for _, spec in ipairs(parent_specs) do
      if node:type() == spec.parent_type then
        local name_node = nodes.find_child_by_type(node, spec.name_node_type)
        local name = ""
        if name_node then
          name = vim.treesitter.get_node_text(name_node, buf)
        end
        table.insert(result, 1, name)
        break
      end
    end
    node = node:parent()
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

local function format_params(params, with_default_values)
  local s = ""
  for _, p in ipairs(params) do
    if #s > 0 then
      s = s .. ", "
    end
    if p.type_qualifier then
      s = s .. p.type_qualifier .. " "
    end
    if p.type then
      s = s .. p.type
    end
    if p.declarator then
      s = s .. " " .. p.declarator
    end
    if with_default_values and p.default_value then
      s = s .. " = " .. p.default_value
    end
  end
  return s
end

local function make_declaration_params(decl, def)
  local params = {}
  for _, p in ipairs(def.params) do
    local default_value = nil
    for _, decl_p in ipairs(decl.params) do
      if decl_p.declarator == p.declarator then
        default_value = decl_p.default_value
      end
    end
    table.insert(params, {
      type_qualifier = p.type_qualifier,
      type = p.type,
      declarator = p.declarator,
      default_value = default_value,
    })
  end
  return params
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
  signature = signature .. decl.name .. "(" .. format_params(decl.params, false) .. ")"
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
  local decl_params = make_declaration_params(decl, def)
  signature = signature
      .. def.type
      .. " "
      .. def.name
      .. "(" .. format_params(decl_params, true) .. ")"
  if def.type_qualifier then
    signature = signature .. " " .. def.type_qualifier
  end
  if decl.has_semicolon then
    signature = signature .. ";"
  end
  return strings.split(signature, "\n")
end

local function function_declarator(decl)
  local signature = qualifier(decl.classes)
  if #signature > 0 then
    signature = signature .. "::"
  end
  signature = signature
      .. decl.name
      .. "(" .. format_params(decl.params) .. ")"
  if decl.type_qualifier then
    signature = signature .. " " .. decl.type_qualifier
  end
  return strings.split(signature, "\n")
end

function M.func_display(func)
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
  signature = signature .. func.name .. "(" .. format_params(func.params, true) .. ")"
  if func.type_qualifier then
    signature = signature .. " " .. func.type_qualifier
  end
  local result = string.gsub(signature, "\n", " ")
  return result
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

local function make_child_scanner(node)
  return { node = node, index = 0 }
end

local function eat_child(scanner)
  if scanner.index >= scanner.node:named_child_count() then
    return nil
  end
  local child = scanner.node:named_child(scanner.index)
  scanner.index = scanner.index + 1
  return child
end

local function eat_child_of_type(scanner, node_type)
  if scanner.index >= scanner.node:named_child_count() then
    return nil
  end
  local child = scanner.node:named_child(scanner.index)
  if child:type() == node_type then
    scanner.index = scanner.index + 1
    return child
  end
  d("eat_child_of_type %s but found %s", node_type, child:type())
  return nil
end

local function eat_any_child(scanner, node_types)
  if scanner.index >= scanner.node:named_child_count() then
    return nil
  end
  local child = scanner.node:named_child(scanner.index)
  for _, node_type in ipairs(node_types) do
    if child:type() == node_type then
      scanner.index = scanner.index + 1
      return child
    end
  end
  d("eat_any_child %s but found %s", vim.inspect(node_types), child:type())
  return nil
end

local function unwrap_declarator(node, func)
  while node and node:type() ~= "function_declarator"
  do
    if node:type() == "pointer_declarator" then
      func.type = func.type .. "*"
      node = nodes.find_child_by_one_of_types(node, possible_declarators)
    elseif node:type() == "reference_declarator" then
      func.type = func.type .. "&"
      node = nodes.find_child_by_one_of_types(node, possible_declarators)
    elseif node:type() == "ERROR" then
      -- special case for `type* Func() ABSL_GUARDED_BY(mutex)`, which is not
      -- a valid syntax
      return nodes.find_child_by_type(node, "function_declarator")
    else
      error("Unxepected child in function declarator "
        .. vim.treesitter.get_node_text(node, func.buf))
    end
  end
  return node
end

local function parse_parameters(parameter_list_node, buf)
  local params = {}
  local scanner = make_child_scanner(parameter_list_node)
  while true do
    local param = {}
    local param_node = eat_any_child(scanner, { "parameter_declaration", "optional_parameter_declaration" })
    if not param_node then
      break
    end
    local param_scanner = make_child_scanner(param_node)
    local type_qualifier = eat_child_of_type(param_scanner, "type_qualifier")
    if type_qualifier then
      param.type_qualifier = vim.treesitter.get_node_text(type_qualifier, buf)
    end
    local type = eat_any_child(param_scanner, possible_types)
    if type then
      param.type = vim.treesitter.get_node_text(type, buf)
    end
    local declarator = eat_any_child(param_scanner, { "identifier", "pointer_declarator", "reference_declarator" })
    if declarator then
      param.declarator = vim.treesitter.get_node_text(declarator, buf)
    end
    -- Any trailing child in the end of the signature is the default value.
    local default_value = eat_child(param_scanner)
    if default_value then
      param.default_value = vim.treesitter.get_node_text(default_value, buf)
    end
    table.insert(params, param)
  end
  return params
end

local function parse_function_declarator(node, func)
  local scanner = make_child_scanner(node)
  local identifier = eat_any_child(scanner, { "identifier", "field_identifier", "destructor_name" })
  if identifier then
    func.name = vim.treesitter.get_node_text(identifier, func.buf)
  end
  local qualified_identifier = eat_child_of_type(scanner, "qualified_identifier")
  if qualified_identifier then
    local parts = vim.split(vim.treesitter.get_node_text(
      qualified_identifier, func.buf), "::")
    for i = 1, #parts - 1 do
      table.insert(func.classes, parts[i])
    end
    func.name = parts[#parts]
  end
  local params = eat_child_of_type(scanner, "parameter_list")
  if not params then
    return nil
  end
  func.params = parse_parameters(params, func.buf)
  local type_qualifier = eat_child_of_type(scanner, "type_qualifier")
  if type_qualifier then
    func.type_qualifier = vim.treesitter.get_node_text(type_qualifier, func.buf)
  end
end

local function parse_function(node, buf)
  if dlog.is_enabled("cpp-companion") then
    d("parse_function node: %s", vim.treesitter.get_node_text(node, buf))
  end
  local func = {
    buf = buf,
    node = node,
    namespaces = collect_named_parents(buf, node, {
      { parent_type = "namespace_definition", name_node_type = "namespace_identifier" },
    }),
    classes = collect_named_parents(buf, node, {
      { parent_type = "class_specifier",  name_node_type = "type_identifier" },
      { parent_type = "struct_specifier", name_node_type = "type_identifier" },
    }),
    type = "",  -- could remain empty for constructors/destructors
    name = "",
    params = {},
    has_semicolon = string.sub(vim.treesitter.get_node_text(node, buf), -1) == ";",
  }
  local scanner = make_child_scanner(node)
  local storage_class = eat_child_of_type(scanner, "storage_class_specifier")
  if storage_class then
    func.storage_class = vim.treesitter.get_node_text(storage_class, func.buf)
  end
  local type_qualifier = eat_child_of_type(scanner, "type_qualifier")
  if type_qualifier then
    func.type = vim.treesitter.get_node_text(type_qualifier, func.buf) .. " "
  end
  local type = eat_any_child(scanner, possible_return_types)
  if type then
    func.type = func.type .. vim.treesitter.get_node_text(type, func.buf)
  end
  local declarator = eat_any_child(scanner, possible_declarators)
  if not declarator then
    return nil
  end
  declarator = unwrap_declarator(declarator, func)
  if not declarator then
    return nil
  end
  if declarator:type() == "function_declarator" then
    parse_function_declarator(declarator, func)
  end
  -- Ignore absl thread annotations, etc.
  if strings.starts_with(func.name, "ABSL_") then
    return nil
  end
  return func
end

local function run_query(buf, node, query_str, opts)
  d("running query %s", query_str)
  opts = opts or {}
  local query = vim.treesitter.query.parse("cpp", query_str)
  local functions = {}
  for _, n in query:iter_captures(node, buf) do
    local func = parse_function(n, buf)
    if func then
      table.insert(functions, func)
    end
  end
  if dlog.is_enabled("cpp-companion") then
    d("found %d functions", #functions)
    for i, f in ipairs(functions) do
      d("%d: %s", i, M.func_display(f))
    end
  end
  return functions
end

local function node_get_definitions(buf, node)
  return run_query(buf, node, "(function_definition) @decl")
end

local function node_get_declarations(buf, node)
  return tables.merge_arrays(
    run_query(buf, node, "(field_declaration) @decl"),
    run_query(buf, node, "(declaration) @decl"))
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

local function buf_get_declarations(buf)
  buf = buf or 0
  local parser = vim.treesitter.get_parser(buf, "cpp")
  local tree = parser:parse()
  local root = tree[1]:root()
  return node_get_declarations(buf, root)
end

local function buf_get_definitions(buf)
  buf = buf or 0
  local parser = vim.treesitter.get_parser(buf, "cpp")
  local tree = parser:parse()
  local root = tree[1]:root()
  return node_get_definitions(buf, root)
end

local function update_declaration_node(decl, def)
  nodes.update_node_text(decl.buf, decl.node, declaration_signature(def, decl))
  vim.notify("Updated declaration " .. fully_qualified_name(def))
end

local function update_definition_node(def, decl)
  local type_node = nodes.find_child_by_one_of_types(def.node, possible_return_types)
  if type_node then
    d("updating type node %s with %s", debug_node_text(type_node, def.buf), decl.type)
    nodes.update_node_text(def.buf, type_node, { decl.type })
  end
  local declarator_node = nodes.find_child_by_one_of_types(def.node,
    { "function_declarator", "reference_declarator", "pointer_declarator" })
  if declarator_node then
    d("updating declarator node %s", debug_node_text(declarator_node, def.buf))
    nodes.update_node_text(def.buf, declarator_node, function_declarator(decl))
    vim.notify("Updated definition " .. fully_qualified_name(decl))
  else
    vim.notify("Could not find definition " .. fully_qualified_name(decl), vim.log.levels.ERROR)
  end
end

function M.sibling_dot_h_header_locator(buf)
  buf = buf or 0
  local filename = vim.api.nvim_buf_get_name(buf)
  return vim.fn.fnamemodify(filename, ":r") .. ".h"
end

function M.get_declarations(buf)
  buf = buf or 0
  local declarations = {}
  local bufs = get_lib_bufs(buf)
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
      lines_from_bottom = 3     -- }, return statement and line above
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
      local signature = M.func_display(decl)
      local start_line = decl.node:start()
      return {
        value = signature,
        ordinal = signature,
        display = signature,
        filename = vim.api.nvim_buf_get_name(decl.buf),
        lnum = start_line + 1,
        decl = decl,
      }
    end,
    on_selected = function(entry)
      insert_signature(entry.decl)
    end,
  })
end

function M.definition_at_cursor(win)
  win = win or 0
  local buf = vim.api.nvim_win_get_buf(win)
  local node = nodes.get_node_at_cursor(win)
  local func = nodes.find_parent_by_type(node, "function_definition")
  if func then
    local definitions = node_get_definitions(buf, func)
    if #definitions == 1 then
      return definitions[1]
    end
  end
  return nil
end

function M.declaration_at_cursor(win)
  win = win or 0
  local buf = vim.api.nvim_win_get_buf(win)
  local node = nodes.get_node_at_cursor(win)
  local field_node = nodes.find_parent_by_type(node, "field_declaration")
  if field_node then
    local declarations = node_get_declarations(buf, field_node)
    if #declarations == 1 then
      return declarations[1]
    end
  end
  local declaration_node = nodes.find_parent_by_type(node, "declaration")
  if declaration_node then
    local declarations = node_get_declarations(buf, declaration_node)
    if #declarations == 1 then
      return declarations[1]
    end
  end
  return nil
end

function M.get_definitions(buf)
  buf = buf or 0
  local definitions = {}
  local bufs = get_lib_bufs(buf)
  for _, b in ipairs(bufs) do
    definitions = tables.merge_arrays(definitions, buf_get_definitions(b))
  end
  return definitions
end

function M.update_declaration(definition)
  local declarations = M.get_declarations(definition.buf)
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
      local signature = M.func_display(decl)
      local start_line = decl.node:start()
      return {
        value = signature,
        ordinal = pair.ordinal,
        display = signature,
        filename = vim.api.nvim_buf_get_name(decl.buf),
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
  local definitions = M.get_definitions(decl.buf)
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
      local signature = M.func_display(def)
      local start_line = def.node:start()
      return {
        value = signature,
        ordinal = pair.ordinal,
        display = signature,
        filename = vim.api.nvim_buf_get_name(def.buf),
        lnum = start_line + 1,
        def = def,
      }
    end,
    on_selected = function(entry)
      update_definition_node(entry.def, decl)
    end,
  })
end

function M.sync_declaration_and_definition(win)
  win = win or 0
  local definition = M.definition_at_cursor(win)
  if definition then
    M.update_declaration(definition)
    return
  end
  local declaration = M.declaration_at_cursor(win)
  if declaration then
    M.update_definition(declaration)
    return
  end
  vim.notify("Could not find a single function definition or declaration at the cursor position", vim.log.levels.INFO)
end

return M
