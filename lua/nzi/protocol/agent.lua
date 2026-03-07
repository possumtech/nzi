local tools = require("nzi.tools.tools");
local resolver = require("nzi.context.resolver");
local protocol = require("nzi.protocol.protocol");
local modal = require("nzi.ui.modal");
local config = require("nzi.core.config");
local context = require("nzi.context.context");
local editor = require("nzi.ui.editor");
local diff = require("nzi.ui.diff");

local M = {};

--- Parse SEARCH/REPLACE blocks from a string (Ultra-Resilient)
local function parse_edit_blocks(content)
  local blocks = {};
  local lines = vim.split(content, "\n");
  local current_block = nil;
  local state = "none";

  for _, line in ipairs(lines) do
    if line:match("^<<<<<<<") then
      current_block = { search = {}, replace = {} };
      state = "search";
    elseif line:match("^=======") then
      state = "replace";
    elseif line:match("^>>>>>>>") then
      if current_block then
        table.insert(blocks, current_block);
        current_block = nil;
      end
      state = "none";
    elseif state == "search" then
      table.insert(current_block.search, line);
    elseif state == "replace" then
      table.insert(current_block.replace, line);
    end
  end
  
  if current_block and state == "replace" then
    table.insert(blocks, current_block);
  end
  
  return blocks;
end

--- Dispatch a set of model actions and return the combined agent responses
--- @param actions table: The parsed model actions
--- @param mode string: 'ask' or 'instruct'
--- @param turn_id number | nil
--- @param callback function: Called with (response, signal, was_blocked)
function M.dispatch_actions(actions, mode, turn_id, callback)
  local queue = require("nzi.core.queue");
  local accumulated_responses = {};
  local was_blocked = false;

  -- Handle optional turn_id (shift arguments if needed)
  if type(turn_id) == "function" then
    callback = turn_id;
    turn_id = nil;
  end
  
  -- Clear turn-level action queue before processing
  queue.clear_actions();

  -- 1. Filter and group actions
  local edits_by_file = {};
  local other_actions = {};
  local restricted = { edit = true, replace_all = true, create = true, delete = true, shell = true, choice = true };
  
  for _, action in ipairs(actions) do
    -- ENFORCEMENT: Block restricted actions in 'ask' mode
    if mode == "ask" and restricted[action.name] then
      table.insert(accumulated_responses, string.format("<agent:status level='error'>Action <%s> blocked: 'ask' mode is read-only. Use 'instruct' (AI:) for modifications.</agent:status>", action.name));
    elseif action.name == "edit" or action.name == "replace_all" then
      queue.enqueue_action(action);
      was_blocked = true;
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          edits_by_file[file] = edits_by_file[file] or {};
          table.insert(edits_by_file[file], action);
        else
          table.insert(accumulated_responses, string.format("<agent:status level='error'>%s</agent:status>", err));
        end
      end
    else
      queue.enqueue_action(action);
      table.insert(other_actions, action);
    end
  end

  -- 2. Process non-edit actions first (recursive chain)
  local function run_others(idx)
    if idx > #other_actions then
      -- 3. After others, process consolidated edits
      local file_list = {};
      for f, _ in pairs(edits_by_file) do table.insert(file_list, f) end
      table.sort(file_list);
      
      local function run_edits(f_idx)
        if f_idx > #file_list then
          -- FINISHED ALL ACTIONS
          if #accumulated_responses > 0 then
            callback(table.concat(accumulated_responses, "\n\n"), nil, was_blocked);
          else
            callback(nil, nil, was_blocked);
          end
          return;
        end

        local file = file_list[f_idx];
        local file_actions = edits_by_file[file];
        local bufnr = vim.fn.bufadd(file);
        vim.fn.bufload(bufnr);
        
        modal.write("Consolidating " .. #file_actions .. " edits for: " .. file, "system", false, turn_id);
        
        -- Start with the current base state
        local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
        local was_modified = false;

        -- Apply all edits for this file sequentially to the same buffer copy
        for _, action in ipairs(file_actions) do
          if action.name == "edit" then
            local blocks = parse_edit_blocks(action.content or "");
            local temp_buf = vim.api.nvim_create_buf(false, true);
            vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, current_lines);
            
            local local_modified = false;
            for _, block in ipairs(blocks) do
              local s, e, q = editor.find_block(temp_buf, block.search);
              if s then
                editor.apply(temp_buf, s, e, block.replace);
                local_modified = true;
                was_modified = true;
              end
            end
            
            if local_modified then
              current_lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false);
            else
              table.insert(accumulated_responses, string.format("<agent:status level='warning'>Some blocks in %s did not match.</agent:status>", file));
            end
            vim.api.nvim_buf_delete(temp_buf, { force = true });

          elseif action.name == "replace_all" then
            current_lines = vim.split(action.content or "", "\n");
            was_modified = true;
          end
        end

        if was_modified then
          if config.options.yolo then
            diff.apply_immediately(bufnr, current_lines);
            table.insert(accumulated_responses, string.format("<agent:status>Consolidated edits applied to %s (YOLO).</agent:status>", file));
          else
            diff.propose_edit(bufnr, current_lines);
            table.insert(accumulated_responses, string.format("<agent:status>Proposed consolidated edits for %s. Awaiting diff.</agent:status>", file));
          end
        else
          table.insert(accumulated_responses, string.format("<agent:status level='error'>No edits could be applied to %s.</agent:status>", file));
        end
        
        run_edits(f_idx + 1);
      end

      run_edits(1);
      return;
    end

    local action = other_actions[idx];
    
    if action.name == "grep" then
      modal.write("Searching universe: " .. action.content, "system", false, turn_id);
      local grep_res = tools.grep(action.content);
      table.insert(accumulated_responses, string.format("<agent:match>\n%s\n</agent:match>", grep_res));
      run_others(idx + 1);

    elseif action.name == "definition" then
      modal.write("LSP Lookup: " .. action.content, "system", false, turn_id);
      local def_res = tools.definition(action.content);
      table.insert(accumulated_responses, string.format("<agent:status>%s</agent:status>", def_res));
      run_others(idx + 1);

    elseif action.name == "env" or action.name == "shell" then
      modal.write("Executing " .. action.name .. ": " .. action.content, "system", false, turn_id);
      local output = tools.shell(action.content, config.options.yolo);
      local resp = "";
      if output and output ~= "" then
        resp = string.format("<agent:ack tool='%s' status='success'>\n%s\n</agent:ack>", action.name, output);
        table.insert(accumulated_responses, resp);
      else
        queue.add_passive(string.format("<agent:ack tool='%s' status='success'/>", action.name));
      end
      run_others(idx + 1);

    elseif action.name == "read" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Reading file: " .. file, "system", false, turn_id);
          context.set_state(file, "active");
          -- ACTIVE result: return full content to model
          local bufnr = vim.fn.bufadd(file);
          vim.fn.bufload(bufnr);
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
          local content_text = table.concat(lines, "\n");
          table.insert(accumulated_responses, string.format("<agent:context file='%s'>\n%s\n</agent:context>", file, content_text));
        else
          table.insert(accumulated_responses, string.format("<agent:status level='error'>%s</agent:status>", err));
        end
      end
      run_others(idx + 1);

    elseif action.name == "drop" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Dropping file: " .. file, "system", false, turn_id);
          context.set_state(file, "map");
          queue.add_passive(string.format("<agent:ack tool='drop' file='%s' status='success'/>", file));
        end
      end
      run_others(idx + 1);

    elseif action.name == "reset" then
      modal.write("Agent requested session reset.", "system", false, turn_id);
      require("nzi.core.commands").run("reset");
      queue.add_passive("<agent:ack tool='reset' status='success'>Session history and context have been reset.</agent:ack>");
      run_others(idx + 1);

    elseif action.name == "create" then
      was_blocked = true;
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file_path = vim.fn.getcwd() .. "/" .. raw_file;
        if vim.fn.filereadable(file_path) == 1 then
          table.insert(accumulated_responses, string.format("<agent:status level='error'>File '%s' already exists.</agent:status>", raw_file));
        else
          modal.write("Creating file: " .. raw_file, "system", false, turn_id);
          local confirmed = config.options.yolo or vim.fn.confirm("AI requests to CREATE file: " .. raw_file, "&Yes\n&No", 1) == 1;
          if confirmed then
            local bufnr = vim.fn.bufadd(raw_file);
            vim.fn.bufload(bufnr);
            local lines = vim.split(action.content or "", "\n");
            if config.options.yolo then
              diff.apply_immediately(bufnr, lines);
              queue.add_passive(string.format("<agent:ack tool='create' file='%s' status='success'/>", raw_file));
            else
              diff.propose_edit(bufnr, lines);
              table.insert(accumulated_responses, string.format("<agent:status>Proposed new file content for %s. Awaiting diff.</agent:status>", raw_file));
            end
          else
            table.insert(accumulated_responses, string.format("<agent:status tool='create' file='%s' status='denied'/>", raw_file));
          end
        end
      end
      run_others(idx + 1);

    elseif action.name == "delete" then
      was_blocked = true;
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Requesting delete: " .. file, "system", false, turn_id);
          if config.options.yolo then
            os.remove(vim.fn.getcwd() .. "/" .. file);
            context.set_state(file, "map");
            table.insert(accumulated_responses, "<agent:status>File deleted (YOLO).</agent:status>");
          else
            diff.propose_deletion(file);
            table.insert(accumulated_responses, string.format("<agent:status>Proposed deletion of %s. Awaiting diff.</agent:status>", file));
          end
        end
      end
      run_others(idx + 1);

    elseif action.name == "summary" then
      local clean_summary = action.content:gsub("\n", " "):gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
      if #clean_summary > 120 then clean_summary = clean_summary:sub(1, 117) .. "..." end
      modal.write(clean_summary, "assistant", false, turn_id);
      config.notify(clean_summary, vim.log.levels.INFO);
      run_others(idx + 1);

    elseif action.name == "choice" then
      local is_headless = (#vim.api.nvim_list_uis() == 0);
      if not is_headless then was_blocked = true; end
      
      modal.open();
      modal.write("User Choice Prompt: " .. action.content, "system", false, turn_id);
      
      -- AUTO-CHOOSE in headless mode (for integration tests)
      if is_headless then
        config.log("Headless mode: Auto-selecting first choice.", "AGENT");
        -- Extract first choice using same logic as tools.choice
        local parts = vim.split(action.content, "- [ ]", { plain = true });
        local first_choice = "Auto-selected first option";
        if #parts > 1 then
          first_choice = parts[2]:gsub("^%s*", ""):gsub("%s*$", "");
        end
        local resp = string.format("<agent:choice>%s</agent:choice>", first_choice);
        table.insert(accumulated_responses, resp);
        run_others(idx + 1);
      else
        tools.choice(action.content, function(choice_res)
          vim.schedule(function()
            if choice_res == "User cancelled selection." or choice_res:match("cancelled") then
              callback(nil, "ABORTED");
            else
              local resp = string.format("<agent:choice>%s</agent:choice>", choice_res);
              table.insert(accumulated_responses, resp);
              run_others(idx + 1);
            end
          end);
        end);
      end
    else
      run_others(idx + 1);
    end
  end

  run_others(1);
end

--- Run automated tests and return failure output
--- @param turn_id number | nil
--- @param callback function
--- @param custom_cmd string | nil
function M.verify_state(turn_id, callback, custom_cmd)
  -- Handle optional turn_id (shift arguments if needed)
  if type(turn_id) == "function" then
    custom_cmd = callback;
    callback = turn_id;
    turn_id = nil;
  end

  local test_cmd = custom_cmd or config.options.auto_test;
  if not test_cmd then callback(nil); return end
  modal.write("Running test: " .. test_cmd, "system", false, turn_id);
  local test_output = vim.fn.systemlist(test_cmd);
  local exit_code = vim.v.shell_error;
  if exit_code ~= 0 then
    local failure_text = table.concat(test_output, "\n");
    modal.write("Test failure detected.", "error", false, turn_id);
    local should_retry = config.options.ralph;
    if not should_retry then
      should_retry = vim.fn.confirm("Test failed. Send output back to AI?", "&Yes\n&No", 1) == 1;
    end
    if should_retry then
      callback(string.format("<agent:test>%s</agent:test>", failure_text));
    else
      callback(nil);
    end
  else
    modal.write("Tests passed.", "system", false, turn_id);
    callback(nil);
  end
end

return M;
