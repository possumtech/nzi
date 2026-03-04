local context = require("nzi.context");
local prompts = require("nzi.prompts");
local job = require("nzi.job");
local diff = require("nzi.diff");
local modal = require("nzi.modal");

local M = {};

--- Execute an nzi: directive to modify code
--- @param instruction string: The code modification instruction
--- @param bufnr number: The buffer to apply the diff against
--- @param include_lsp boolean | nil
function M.run(instruction, bufnr, include_lsp)
  local config = require("nzi.config");
  local model_name = config.options.default_model;
  local target_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  local ctx_list = context.gather();
  local prompt_parts = prompts.gather();
  
  local system_prompt = prompts.build_system_prompt(prompt_parts, model_name);
  local context_str = prompts.format_context(ctx_list, include_lsp);
  local full_prompt = prompts.build_directive_prompt(instruction, target_file, prompt_parts, context_str);
  
  -- Use the modal for status updates
  modal.open();
  modal.write(system_prompt .. "\n", "system", false);
  modal.write(context_str .. "\n", "system", false);
  modal.write(instruction .. " (File: " .. target_file .. ")\n", "directive", false);
  
  modal.set_thinking(true);
  job.run(full_prompt, function(success, result)
    vim.schedule(function()
      modal.set_thinking(false);
      if success then
        modal.write("Code change received. Opening diff view...\n", "system", false);
        modal.write(result .. "\n", "response", false);
        diff.open_diff(bufnr, result);
      else
        modal.write("\nERROR: " .. result .. "\n", "system", false);
      end
    end);
  end);
end

return M;
