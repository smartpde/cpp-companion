local M = {}

function M.unsurround(s, l, r)
  local i = 1
  local j = #s
  if string.sub(s, 1, 1) == l then
    i = i + 1
  end
  if string.sub(s, -1) == r then
    j = j - 1
  end
  return string.sub(s, i, j)
end

function M.surround(s, l, r)
  r = r or l
  return l .. s .. r
end

function M.unquote(s)
  return M.unsurround(s, "\"")
end

function M.split(s, delimiter)
  local split = {}
  local matches = string.gmatch(s, "[^" .. delimiter .. "]+")
  for m in matches do
    table.insert(split, m)
  end
  return split
end

function M.trim(s)
  local l = 1
  while string.sub(s, l, l) == ' ' do
    l = l + 1
  end
  local r = #s
  while string.sub(s, r, r) == ' ' do
    r = r - 1
  end
  return string.sub(s, l, r)
end

function M.starts_with(s, prefix)
  return string.sub(s, 1, string.len(prefix)) == prefix
end

return M
