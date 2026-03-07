local diff = require("nzi.ui.diff");
local shell = require("nzi.tools.shell");
local config = require("nzi.core.config");
local M = {};

--- Dispatch a declarative model action to the appropriate Vim side-effect
--- @param action table: { name, attr, content }
--- @param turn_id number
function M.dispatch(action, turn_id)
  local protocol = require("nzi.dom.parser");
  
  if action.name == "edit" or action.name == "replace_all" then
    local raw_file = protocol.get_attr(action.attr, "file");
    if raw_file then
      local resolver = require("nzi.dom.resolver");
      local file, err = resolver.resolve(raw_file);
      if file then
        local editor = require("nzi.ui.editor");
        local bufnr = vim.fn.bufadd(file);
        vim.fn.bufload(bufnr);
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
        
        local success, new_lines = false, {};
        if action.content:match("^```") then
          -- Full file replacement (Markdown block)
          local content = action.content:gsub("^```%w*\n", ""):gsub("\n```$", "");
          new_lines = vim.split(content, "\n");
          success = true;
        else
          -- Surgical SEARCH/REPLACE
          success, new_lines = editor.apply_replacement(lines, action.content);
        end

        if success then
          diff.propose_edit(bufnr, new_lines);
        end
      end
    end

  elseif action.name == "shell" then
    M.run_shell(action.content);

  elseif action.name == "create" then
    local raw_file = protocol.get_attr(action.attr, "file");
    if raw_file then
      local bufnr = vim.fn.bufadd(raw_file);
      vim.fn.bufload(bufnr);
      local lines = vim.split(action.content or "", "\n");
      diff.propose_edit(bufnr, lines);
    end

  elseif action.name == "delete" then
    local raw_file = protocol.get_attr(action.attr, "file");
    if raw_file then
      diff.propose_deletion(raw_file);
    end
  end
end

--- Execute a shell command
function M.run_shell(cmd, bufnr, line_idx, inject)
  shell.run(cmd, bufnr, line_idx, inject);
end

return M;
