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

function M.map(array, f)
  local result = {}
  for _, entry in ipairs(array) do
    table.insert(result, f(entry))
  end
  return result
end

return M
