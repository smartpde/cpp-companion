local M = {}

local function select_with_telescope(opts)
  local pickers = require("telescope.pickers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewer
  if opts.preview_func then
    previewer = previewers.new_buffer_previewer({
      title = opts.preview_title,
      define_preview = function(self, entry)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false,
          opts.preview_func(entry))
      end
    })
  else
    previewer = conf.qflist_previewer({})
  end
  pickers.new({}, {
    prompt_title = opts.prompt .. ": ",
    finder = finders.new_table({
      results = opts.values,
      entry_maker = opts.entry_func
    }),
    sorter = conf.file_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          opts.on_selected(selection)
        end
      end)
      return true
    end
  }):find()
end

local function select_with_native_ui(opts)
  local entry_dict = {}
  local values = {}
  for _, v in ipairs(opts.values) do
    local entry = opts.entry_func(v)
    table.insert(values, entry.value)
    entry_dict[entry.value] = entry
  end
  table.sort(values)
  vim.ui.select(values, { prompt = opts.prompt .. ": " }, function(selected)
    if selected then
      opts.on_selected(entry_dict[selected])
    end
  end)
end

function M.select(opts)
  if pcall(require, "telescope") then
    select_with_telescope(opts)
  else
    select_with_native_ui(opts)
  end
end

function M.to_ordinal_pairs(list)
  local result = {}
  for i, item in ipairs(list) do
    table.insert(result, {item = item, ordinal = tostring(i)})
  end
  return result
end

return M
