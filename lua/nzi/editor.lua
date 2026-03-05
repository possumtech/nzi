local M = {};

--- Find a block of lines in a buffer using a multi-stage matcher
--- @param bufnr number
--- @param search_lines table
--- @return number | nil: Start line (1-indexed)
--- @return number | nil: End line (1-indexed)
function M.find_block(bufnr, search_lines)
  if #search_lines == 0 then return nil end
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
  
  -- Stage 1: Exact Match
  for i = 1, #buffer_lines - #search_lines + 1 do
    local match = true;
    for j = 1, #search_lines do
      if buffer_lines[i + j - 1] ~= search_lines[j] then
        match = false;
        break;
      end
    end
    if match then return i, i + #search_lines - 1 end
  end

  -- Stage 2: Normalized Indentation Match
  local function normalize(line)
    return line:gsub("^%s*", ""):gsub("%s*$", ""):gsub("%s+", " ")
  end

  local norm_search = {};
  for _, l in ipairs(search_lines) do table.insert(norm_search, normalize(l)) end

  for i = 1, #buffer_lines - #search_lines + 1 do
    local match = true;
    for j = 1, #search_lines do
      if normalize(buffer_lines[i + j - 1]) ~= norm_search[j] then
        match = false;
        break;
      end
    end
    if match then return i, i + #search_lines - 1 end
  end

  -- Stage 3: Anchor-based search (match first and last line of block)
  -- Good for when models omit the middle of a large function
  if #search_lines > 2 then
    local first = norm_search[1]
    local last = norm_search[#norm_search]
    for i = 1, #buffer_lines do
      if normalize(buffer_lines[i]) == first then
        for k = i + 1, #buffer_lines do
          if normalize(buffer_lines[k]) == last then
            -- We found anchors. This is risky but often what the model intends.
            -- We only accept if the distance is "reasonable" (e.g. search block size * 2)
            if (k - i) < (#search_lines * 2) then
              return i, k
            end
          end
        end
      end
    end
  end

  return nil, nil
end

--- Apply a replacement to a buffer
--- @param bufnr number
--- @param start_line number: 1-indexed
--- @param end_line number: 1-indexed
--- @param replace_lines table
function M.apply(bufnr, start_line, end_line, replace_lines)
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, replace_lines);
end

return M;
