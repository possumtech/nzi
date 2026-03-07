local config = require("nzi.core.config");
local sitter = require("nzi.service.vim.sitter");
local prompts = require("nzi.service.llm.prompt");

local M = {};

-- Map of buffer IDs to their state
-- States: 'active' (read/write), 'read' (read-only context), 'ignore' (no context)
M.states = {};

--- Get the current state of a buffer
function M.get_state(bufnr)
  if not bufnr or bufnr <= 0 then return "ignore" end
  if bufnr > 1000 and not vim.api.nvim_buf_is_valid(bufnr) then
    return "ignore";
  end
  if M.states[bufnr] then return M.states[bufnr]; end

  local full_path = vim.api.nvim_buf_get_name(bufnr);
  if full_path == "" then return "ignore"; end
  if M.is_git_ignored(full_path) then return "ignore"; end

  return "active";
end

--- Set the state of a buffer
function M.set_state(bufnr_or_path, state)
  local bufnr;
  if type(bufnr_or_path) == "number" then
    bufnr = bufnr_or_path;
  else
    local num = tonumber(bufnr_or_path);
    if num then bufnr = num; else
      local ok, res = pcall(vim.fn.bufadd, bufnr_or_path);
      if ok then bufnr = res; end
    end
  end
  if not bufnr or type(bufnr) ~= "number" or bufnr == -1 then return end
  
  if state == "map" then
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      local is_modified = vim.api.nvim_get_option_value("modified", { buf = bufnr });
      local windows = vim.fn.win_findbuf(bufnr);
      if not is_modified and #windows == 0 then
        vim.api.nvim_buf_delete(bufnr, { unload = false });
      end
    end
    M.states[bufnr] = nil;
    return;
  end

  local valid_states = { active = true, read = true, ignore = true };
  if valid_states[state] then
    M.states[bufnr] = state;
    if (state == "active" or state == "read") and vim.api.nvim_buf_is_valid(bufnr) and not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr);
    end
  end
end

function M.is_git_ignored(path)
  if path == "" then return true; end
  vim.fn.system(string.format("git check-ignore -q '%s'", path));
  return vim.v.shell_error == 0;
end

function M.is_real_buffer(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then return false; end
  if not vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) then return false; end
  local name = vim.api.nvim_buf_get_name(bufnr);
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr });
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr });
  if buftype ~= "" and buftype ~= "acwrite" then return false; end
  local opts = config.options.context or { ignore_filetypes = {} };
  for _, ft in ipairs(opts.ignore_filetypes or {}) do
    if filetype == ft then return false; end
  end
  local short_name = vim.fn.fnamemodify(name, ":.");
  if short_name == "" or short_name == "." or short_name:match("^%s*$") then return false; end
  return true;
end

function M.get_universe()
  local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):match("true");
  if not is_git then return {}; end
  local files = vim.fn.systemlist("git ls-files --cached --exclude-standard 2>/dev/null");
  if vim.v.shell_error ~= 0 then return {}; end
  local universe = {};
  local seen = {};
  for _, path in ipairs(files) do
    -- Remove quotes if git escaped the path
    local clean_path = path:gsub("^\"", ""):gsub("\"$", "");
    if clean_path ~= "" and not seen[clean_path] then
      table.insert(universe, clean_path);
      seen[clean_path] = true;
    end
  end
  table.sort(universe);
  return universe;
end

function M.sync_list()
  local universe = M.get_universe();
  local buffers = vim.api.nvim_list_bufs();
  local ctx_list = {};
  local handled_files = {};

  for _, bufnr in ipairs(buffers) do
    if M.is_real_buffer(bufnr) then
      local full_path = vim.api.nvim_buf_get_name(bufnr);
      local name = vim.fn.fnamemodify(full_path, ":.");
      local state = M.get_state(bufnr);
      handled_files[name] = true;
      if state ~= "ignore" then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
        local content = table.concat(lines, "\n");
        table.insert(ctx_list, {
          bufnr = bufnr, name = name, state = state,
          content = content, size = #content,
        });
      end
    end
  end

  for _, path in ipairs(universe) do
    if not handled_files[path] then
      local content, err = sitter.get_skeleton(path);
      table.insert(ctx_list, {
        bufnr = nil, name = path, state = "map",
        content = content, err = err,
        size = vim.fn.getfsize(path),
      });
    end
  end
  return ctx_list;
end

M.gather = M.sync_list;

function M.sync()
  local ctx_list = M.sync_list();
  return dom_session.format_context(ctx_list, true);
end

function M.get_selection()
  local bridge = require("nzi.service.llm.bridge");
  local sel = bridge.get_visual_selection();
  if sel.text == "" then return nil end
  return sel;
end

return M;
