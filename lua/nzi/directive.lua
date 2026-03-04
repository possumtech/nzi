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
  local target_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  
  local messages, system_prompt, context_str = prompts.build_messages(instruction, "directive", target_file, include_lsp);
  local hist_str = require("nzi.history").format();
  
  -- Use the modal for status updates
  modal.open();
  
  if config.options.modal.show_context then
    modal.write(system_prompt, "system", false);
    if hist_str ~= "" then
      modal.write(hist_str, "history", false);
    end
    modal.write(context_str, "context", false);
  end

  modal.write(instruction .. " (File: " .. target_file .. ")", "directive", config.options.modal.show_context);
  
  modal.set_thinking(true);
  job.run(messages, function(success, result)
    vim.schedule(function()
      modal.set_thinking(false);
      if success and result then
        -- Add to structured history for the next turn
        require("nzi.history").add("directive", instruction, result);
        
        modal.write("Code change received. Opening diff view...\n", "system", false);
        modal.write(result .. "\n", "response", false);
        diff.open_diff(bufnr, result);
      else
        modal.write("\nERROR: " .. (result or "no response received") .. "\n", "system", false);
      end
    end);
  end);
end

return M;
