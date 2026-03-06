local context = require("nzi.context.context");
local prompts = require("nzi.engine.prompts");
local job = require("nzi.engine.job");
local diff = require("nzi.ui.diff");
local modal = require("nzi.ui.modal");

local M = {};

--- Execute an nzi: instruct to modify code
--- @param instruction string: The code modification instruction
--- @param bufnr number: The buffer to apply the diff against
--- @param include_lsp boolean | nil
function M.run(instruction, bufnr, include_lsp)
  local config = require("nzi.core.config");
  local target_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  
  -- Capture buffer context as selection
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
  local selection = {
    text = table.concat(lines, "\n"),
    file = target_file,
    start_line = 1,
    start_col = 1,
    end_line = #lines,
    end_col = #(lines[#lines] or ""),
    mode = "V"
  };

  local messages, system_prompt, context_str, ctx_list, turn_block = prompts.build_messages(instruction, "instruct", target_file, include_lsp, selection);
  local hist_str = require("nzi.context.history").format();
  
  -- Use the modal for status updates
  modal.open();
  
  if config.options.modal.show_context then
    modal.write(system_prompt, "system", false);
    if hist_str ~= "" then
      modal.write(hist_str, "history", false);
    end
    modal.write(context_str, "context", false);
  end

  -- Summary for user feedback
  local counts = { active = 0, read = 0, map = 0 };
  local warnings = {};
  for _, item in ipairs(ctx_list) do
    counts[item.state] = (counts[item.state] or 0) + 1;
    if item.err then table.insert(warnings, string.format("Warning (%s): %s", item.name, item.err)) end
  end
  local summary = string.format("Context: %d active, %d read, %d mapped.", counts.active, counts.read, counts.map);
  modal.write(summary, "system", false);
  for _, w in ipairs(warnings) do modal.write(w, "error", false) end

  modal.write(instruction .. " (File: " .. target_file .. ")", "instruct", config.options.modal.show_context);
  
  modal.set_thinking(true);
  job.run(messages, function(success, result)
    vim.schedule(function()
      modal.set_thinking(false);
      if success and result then
        -- Add to structured history for the next turn
        require("nzi.context.history").add("instruct", instruction, result);
        
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
