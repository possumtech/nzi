local diff = require("nzi.ui.diff");
local run_tool = require("nzi.tools.run");
local config = require("nzi.core.config");
local M = {};

--- Propose a surgical edit via vimdiff
--- @param params table: { file, blocks }
function M.propose_edit(params)
  local file = params.file;
  local blocks = params.blocks;
  if not file or not blocks then return end

  local resolver = require("nzi.dom.resolver");
  local full_path, err = resolver.resolve(file);
  if not full_path then
    config.notify("Could not resolve file: " .. tostring(file), vim.log.levels.ERROR);
    return;
  end

  local bufnr = vim.fn.bufadd(full_path);
  vim.fn.bufload(bufnr);
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
  
  -- Use a temporary buffer to apply surgical blocks
  local editor = require("nzi.ui.editor");
  local temp_buf = vim.api.nvim_create_buf(false, true);
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, current_lines);
  
  local any_match = false;
  for _, block in ipairs(blocks) do
    -- Split multi-line strings into tables for the editor
    local search_lines = vim.split(block.search or "", "\n");
    local replace_lines = vim.split(block.replace or "", "\n");
    
    local s, e = editor.find_block(temp_buf, search_lines);
    if s then
      editor.apply(temp_buf, s, e, replace_lines);
      any_match = true;
    end
  end

  if any_match then
    local new_lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false);
    diff.propose_edit(bufnr, new_lines);
  else
    config.notify("Could not find matching blocks in " .. file, vim.log.levels.WARN);
  end
  vim.api.nvim_buf_delete(temp_buf, { force = true });
end

--- Propose a new file creation
function M.propose_create(params)
  local file = params.file;
  local content = params.content or "";
  if not file then return end

  local bufnr = vim.fn.bufadd(file);
  vim.fn.bufload(bufnr);
  local lines = vim.split(content, "\n");
  diff.propose_edit(bufnr, lines);
end

--- Propose a file deletion
function M.propose_delete(params)
  local file = params.file;
  if not file then return end
  diff.propose_deletion(file);
end

--- Propose a multiple choice question to the user
--- @param params table: { content }
function M.propose_choice(params)
  local content = params.content;
  if not content then return end
  
  local tools = require("nzi.tools.tools");
  local history = require("nzi.dom.session");
  
  tools.choice(content, function(answer)
    if answer then
      history.add_turn({
        type = "answer",
        status = "pass",
        content = answer
      }, "<selection type='answer'>" .. answer .. "</selection>");
    end
  end);
end

--- Execute a system command
function M.run(cmd, bufnr, line_idx, inject, signal_type)
  run_tool.run(cmd, bufnr, line_idx, inject, signal_type);
end


return M;
