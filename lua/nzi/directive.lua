local context = require("nzi.context");
local prompts = require("nzi.prompts");
local job = require("nzi.job");
local diff = require("nzi.diff");
local modal = require("nzi.modal");

local M = {};

--- Execute an nzi: directive to modify code
--- @param instruction string: The code modification instruction
--- @param bufnr number: The buffer to apply the diff against
function M.run(instruction, bufnr)
  local target_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  local ctx_list = context.gather();
  local prompt_parts = prompts.gather();
  
  local context_str = prompts.format_context(ctx_list);
  local full_prompt = prompts.build_directive_prompt(instruction, target_file, prompt_parts, context_str);
  
  -- Use the modal for status updates
  modal.write("# nzi: Modifying Code...\n\nProcessing: " .. instruction, false);
  modal.open();
  
  job.run(full_prompt, function(success, result)
    vim.schedule(function()
      if success then
        modal.write("# nzi: Success\n\nCode change received. Opening diff view...", false);
        diff.open_diff(bufnr, result);
      else
        modal.write("# nzi: Error\n\n" .. result, false);
      end
    end);
  end);
end

return M;
