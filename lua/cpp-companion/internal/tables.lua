local M = {}

function M.merge_arrays(...)
  local result = {}
  local n = select("#", ...)
  for i = 1, n do
    for _, v in ipairs(select(i, ...)) do
      table.insert(result, v)
    end
  end
  return result
end

return M
