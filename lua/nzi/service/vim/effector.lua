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
        if action.name == "replace_all" or (action.content and action.content:match("^```")) then
          -- Full file replacement (Markdown block or replace_all)
          local content = action.content or ""
          if content:match("^```") then
            content = content:gsub("^```%w*\n", ""):gsub("\n```$", "");
          end
          new_lines = vim.split(content, "\n");
          success = true;
        else
          -- Surgical SEARCH/REPLACE using pre-parsed blocks
          local blocks = action.blocks or {};
          if #blocks > 0 then
            local temp_buf = vim.api.nvim_create_buf(false, true);
            vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines);
            local any_match = false;
            for _, block in ipairs(blocks) do
              local s, e, q = editor.find_block(temp_buf, block.search);
              if s then
                editor.apply(temp_buf, s, e, block.replace);
                any_match = true;
              end
            end
            if any_match then
              new_lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false);
              success = true;
            end
            vim.api.nvim_buf_delete(temp_buf, { force = true });
          end
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
  shell.run_shell(cmd, bufnr, line_idx, inject);
end

return M;
