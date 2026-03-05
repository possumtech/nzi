local M = {};

--- Find a block of lines in a buffer using a multi-stage matcher
--- @param bufnr number
--- @param search_lines table
--- @return number | nil: Start line (1-indexed)
--- @return number | nil: End line (1-indexed)
--- @return string | nil: Match quality ('perfect', 'normalized', 'regex', 'best_fit')
function M.find_block(bufnr, search_lines)
  if not search_lines or #search_lines == 0 then return nil end
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
  
  local function normalize(line)
    if not line then return "" end
    local res = line:gsub("^%s*", ""):gsub("%s*$", ""):gsub("%s+", " ")
    return res
  end

  -- Stage 1: Exact Match
  for i = 1, #buffer_lines - #search_lines + 1 do
    local match = true;
    for j = 1, #search_lines do
      if buffer_lines[i + j - 1] ~= search_lines[j] then
        match = false;
        break;
      end
    end
    if match then return i, i + #search_lines - 1, "perfect" end
  end

  -- Stage 2: Normalized Match
  local norm_search = {};
  for _, l in ipairs(search_lines) do 
    table.insert(norm_search, normalize(l)) 
  end

  for i = 1, #buffer_lines - #search_lines + 1 do
    local match = true;
    for j = 1, #search_lines do
      if normalize(buffer_lines[i + j - 1]) ~= norm_search[j] then
        match = false;
        break;
      end
    end
    if match then return i, i + #search_lines - 1, "normalized" end
  end

  -- Stage 3: Regex/Pattern Match
  local has_patterns = false;
  for _, l in ipairs(search_lines) do
    if l:match("[%[%]%(%)%.%*%+%-%?%^%$]") then has_patterns = true; break end
  end

  if has_patterns then
    for i = 1, #buffer_lines - #search_lines + 1 do
      local match = true;
      for j = 1, #search_lines do
        local ok, matched = pcall(string.match, buffer_lines[i + j - 1], search_lines[j]);
        if not ok or not matched then
          match = false;
          break;
        end
      end
      if match then return i, i + #search_lines - 1, "regex" end
    end
  end

  -- Stage 4: Sliding Window "Best Fit" (Highest % of normalized matches)
  local best_start = nil
  local best_score = 0
  local threshold = 0.6 

  for i = 1, #buffer_lines - #search_lines + 1 do
    local matches = 0
    for j = 1, #search_lines do
      if normalize(buffer_lines[i + j - 1]) == norm_search[j] then
        matches = matches + 1
      end
    end
    
    local score = matches / #search_lines
    if score > best_score then
      best_score = score
      best_start = i
    end
  end

  if best_score >= threshold then
    return best_start, best_start + #search_lines - 1, "best_fit"
  end

  -- Stage 5: Anchor Match fallback (match first and last normalized lines)
  if #search_lines > 1 then
    local first = norm_search[1]
    local last = norm_search[#norm_search]
    for i = 1, #buffer_lines do
      if normalize(buffer_lines[i]) == first then
        for k = i + 1, math.min(i + #search_lines * 3, #buffer_lines) do
          if normalize(buffer_lines[k]) == last then
            return i, k, "best_fit"
          end
        end
      end
    end
  end

  return nil, nil, nil
end

--- Apply a replacement to a buffer
function M.apply(bufnr, start_line, end_line, replace_lines)
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, replace_lines);
end

return M;
