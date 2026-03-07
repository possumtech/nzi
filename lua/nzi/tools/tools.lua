local context = require("nzi.service.vim.watcher");
local config = require("nzi.core.config");

local M = {};

--- Execute a grep search across the project universe (Active + Read files)
--- @param pattern string: The search pattern
--- @return string: The formatted <agent:grep> output
function M.grep(pattern)
  local ctx_list = context.gather();
  local results = {};
  
  for _, item in ipairs(ctx_list) do
    -- Only grep files the model is allowed to "see" (Active or Read)
    -- We skip 'map' (skeletons) as the model needs to 'read' those first to grep them,
    -- OR we can allow grepping skeletons if we want it to be more powerful?
    -- Decision: Let's allow grepping everything in the universe (Active/Read/Map) 
    -- but NOT Ignore. This makes discovery much faster.
    if item.state ~= "ignore" then
      local path = item.name;
      local full_path = vim.fn.getcwd() .. "/" .. path;
      
      -- If it's a buffer, use buffer lines for accuracy (unsaved changes)
      local lines = {};
      if item.bufnr and vim.api.nvim_buf_is_loaded(item.bufnr) then
        lines = vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false);
      elseif vim.fn.filereadable(full_path) == 1 then
        lines = vim.fn.readfile(full_path);
      end
      
      for i, line in ipairs(lines) do
        if line:find(pattern, 1, true) then
          -- Escape & < > in the line content for XML safety
          local clean_line = line:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;");
          table.insert(results, string.format("<agent:match file=\"%s\" line=\"%d\">%s</agent:match>", path, i, clean_line));
        end
      end
    end
  end
  
  if #results == 0 then
    return "No matches found in project universe.";
  end
  
  return table.concat(results, "\n");
end

--- Execute a shell/env command with user permission
--- @param command string: The shell command
--- @param is_yolo boolean: Whether to skip permission prompts
--- @return string | nil: The output if the user wants to return it to context, else nil
function M.shell(command, is_yolo)
  local confirmed = is_yolo;
  
  if not confirmed then
    local choice = vim.fn.confirm("AI requests shell command: " .. command, "&Yes\n&No", 2);
    confirmed = (choice == 1);
  end
  
  if not confirmed then
    return "User denied shell command execution.";
  end
  
  local output = vim.fn.systemlist(command);
  local result_text = table.concat(output, "\n");
  
  local send_to_context = is_yolo;
  if not send_to_context then
    local choice = vim.fn.confirm("Send command output back to AI context?", "&Yes\n&No", 1);
    send_to_context = (choice == 1);
  end
  
  if send_to_context then
    return result_text;
  end
  
  return nil; -- Command ran, but result stays local
end

--- Present a multiple-choice ask to the user using vim.ui.select
--- @param content string: The ask and checkbox list from the model
--- @param callback function: Called with the final user answer string
function M.choice(content, callback)
  -- 1. Extract the prompt and options using a flexible split
  -- We split on common markdown checkbox patterns: "- [ ]" or "* [ ]"
  -- We use Lua patterns: escape [ and ] as %[ and %]
  local parts = vim.split(content, "[-*]%s*%[%s*%]", { trimempty = false });
  
  local prompt = parts[1]:gsub("^%s*", ""):gsub("%s*$", "");
  local options = {};
  
  for i = 2, #parts do
    local opt = parts[i]:gsub("^%s*", ""):gsub("%s*$", "");
    -- If the option contains newlines, it might be a multi-line prompt 
    -- where the next option starts on a new line. We want to trim those.
    -- But usually, each part after the split is a single option.
    if opt ~= "" then
      -- If there's a newline, only take the first line as the option text
      -- to avoid consuming the next prompt lines if the model is messy.
      local opt_lines = vim.split(opt, "\n");
      local clean_opt = opt_lines[1]:gsub("^%s*", ""):gsub("%s*$", "");
      if clean_opt ~= "" then
        table.insert(options, clean_opt);
      end
    end
  end

  if prompt == "" then prompt = "Please choose an option:"; end

  -- 2. Fallback: If fewer than 2 options found, provide Yes/No
  if #options < 2 then
    options = { "Yes", "No" };
    prompt = content:gsub("^%s*", ""):gsub("%s*$", "");
  end
  
  -- 3. Append the mandatory "Freeform Response" option
  table.insert(options, "None of the above (Respond with text)");
  
  -- 4. Show the UI
  vim.ui.select(options, {
    prompt = prompt,
  }, function(choice, index)
    if not choice then
      callback("User cancelled selection.");
      return;
    end
    
    if index == #options then
      -- User chose "Freeform Response"
      vim.ui.input({ prompt = "Your response: " }, function(input)
        callback(input or "User provided no text response.");
      end);
    else
      callback(choice);
    end
  end);
end

--- Find the definition of a symbol using LSP
--- @param symbol string: The symbol to look up
--- @return string: The location or error message
function M.definition(symbol)
  -- We search for the symbol in all active buffers
  -- This is slightly non-standard LSP but works well for agentic discovery
  local results = {};
  local params = { textDocument = vim.lsp.util.make_text_document_params(), position = nil };
  
  -- Heuristic: Try to find the symbol in current buffer first
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false);
  for i, line in ipairs(lines) do
    local col = line:find(symbol, 1, true);
    if col then
      -- Trigger LSP request at this position
      local win = vim.api.nvim_get_current_win();
      local original_pos = vim.api.nvim_win_get_cursor(win);
      vim.api.nvim_win_set_cursor(win, { i, col - 1 });
      
      -- Synchronous wait for LSP response (short timeout)
      local lsp_res = vim.lsp.buf_request_sync(0, "textDocument/definition", vim.lsp.util.make_position_params(), 1000);
      vim.api.nvim_win_set_cursor(win, original_pos);
      
      if lsp_res then
        for _, server_res in pairs(lsp_res) do
          if server_res.result then
            local location = server_res.result[1] or server_res.result;
            if location.uri or location.targetUri then
              local uri = location.uri or location.targetUri;
              local range = location.range or location.targetSelectionRange;
              local path = vim.uri_to_fname(uri);
              local rel_path = vim.fn.fnamemodify(path, ":.");
              table.insert(results, string.format("%s:%d", rel_path, range.start.line + 1));
            end
          end
        end
      end
      if #results > 0 then break end
    end
  end

  if #results == 0 then
    return "LSP definition not found for: " .. symbol;
  end
  
  return "Definition found at: " .. table.concat(results, ", ");
end

return M;
