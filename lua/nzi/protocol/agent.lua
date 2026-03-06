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
--- @param callback function: Called with (response, signal, was_blocked)
function M.dispatch_actions(actions, mode, callback)
  local queue = require("nzi.core.queue");
  local current_idx = 1;
  local accumulated_responses = {};
  local was_blocked = false;
  
  -- Clear turn-level action queue before processing
  queue.clear_actions();

  -- 1. Filter and group actions
  local edits_by_file = {};
  local other_actions = {};
  local restricted = { edit = true, replace_all = true, create = true, delete = true, shell = true, choice = true };
  
  for _, action in ipairs(actions) do
    -- ENFORCEMENT: Block restricted actions in 'ask' mode
    if mode == "ask" and restricted[action.name] then
      table.insert(accumulated_responses, string.format("<agent:status>Action <%s> blocked: 'ask' mode is read-only. Use 'instruct' (AI:) for modifications.</agent:status>", action.name));
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
          table.insert(accumulated_responses, string.format("<agent:status>Error: %s</agent:status>", err));
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
          queue.clear_actions();
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
        
        modal.write("Consolidating " .. #file_actions .. " edits for: " .. file, "system", false);
        
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
              table.insert(accumulated_responses, string.format("<agent:status>Warning: Some blocks in %s did not match.</agent:status>", file));
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
          table.insert(accumulated_responses, string.format("<agent:status>Error: No edits could be applied to %s.</agent:status>", file));
        end
        
        run_edits(f_idx + 1);
      end

      run_edits(1);
      return;
    end

    local action = other_actions[idx];
    
    if action.name == "grep" then
      modal.write("Searching universe: " .. action.content, "system", false);
      local grep_res = tools.grep(action.content);
      table.insert(accumulated_responses, string.format("<agent:grep>\n%s\n</agent:grep>", grep_res));
      run_others(idx + 1);

    elseif action.name == "definition" then
      modal.write("LSP Lookup: " .. action.content, "system", false);
      local def_res = tools.definition(action.content);
      table.insert(accumulated_responses, string.format("<agent:status>%s</agent:status>", def_res));
      run_others(idx + 1);

    elseif action.name == "env" or action.name == "shell" then
      modal.write("Executing " .. action.name .. ": " .. action.content, "system", false);
      local output = tools.shell(action.content, config.options.yolo);
      local resp = "";
      if output then
        resp = string.format("<agent:%s>\n%s\n</agent:%s>", action.name, output, action.name);
      else
        resp = string.format("<agent:%s>Command executed. No output returned to context.</agent:%s>", action.name, action.name);
      end
      table.insert(accumulated_responses, resp);
      run_others(idx + 1);

    elseif action.name == "read" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Reading file: " .. file, "system", false);
          context.set_state(file, "active");
          table.insert(accumulated_responses, "<agent:status>File read and added to active context.</agent:status>");
        else
          table.insert(accumulated_responses, string.format("<agent:status>Error: %s</agent:status>", err));
        end
      end
      run_others(idx + 1);

    elseif action.name == "drop" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Dropping file: " .. file, "system", false);
          context.set_state(file, "map");
          table.insert(accumulated_responses, "<agent:status>File dropped to project map.</agent:status>");
        end
      end
      run_others(idx + 1);

    elseif action.name == "reset" then
      modal.write("Agent requested session reset.", "system", false);
      require("nzi.core.commands").run("reset");
      table.insert(accumulated_responses, "<agent:status>Session history and context have been reset.</agent:status>");
      run_others(idx + 1);

    elseif action.name == "create" then
      was_blocked = true;
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file_path = vim.fn.getcwd() .. "/" .. raw_file;
        if vim.fn.filereadable(file_path) == 1 then
          table.insert(accumulated_responses, string.format("<agent:status>Error: File '%s' already exists. Use <model:edit> or <model:replace_all> to modify existing files.</agent:status>", raw_file));
        else
          modal.write("Creating file: " .. raw_file, "system", false);
          local confirmed = config.options.yolo or vim.fn.confirm("AI requests to CREATE file: " .. raw_file, "&Yes\n&No", 1) == 1;
          if confirmed then
            local bufnr = vim.fn.bufadd(raw_file);
            vim.fn.bufload(bufnr);
            local lines = vim.split(action.content or "", "\n");
            if config.options.yolo then
              diff.apply_immediately(bufnr, lines);
              table.insert(accumulated_responses, "<agent:status>File created and content applied (YOLO).</agent:status>");
            else
              diff.propose_edit(bufnr, lines);
              table.insert(accumulated_responses, "<agent:status>Proposed new file content. Awaiting diff.</agent:status>");
            end
          else
            table.insert(accumulated_responses, "<agent:status>File creation denied by user.</agent:status>");
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
          modal.write("Requesting delete: " .. file, "system", false);
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
      modal.write(action.content, "assistant", false);
      config.notify(action.content, vim.log.levels.INFO);
      run_others(idx + 1);

    elseif action.name == "choice" then
      was_blocked = true;
      modal.open();
      modal.write("User Choice Prompt: " .. action.content, "system", false);
      tools.choice(action.content, function(choice_res)
        vim.schedule(function()
          if choice_res == "User cancelled selection." or choice_res:match("cancelled") then
            -- HALT SIGNAL: Return nil to callback to stop the engine loop
            callback(nil, "ABORTED");
          else
            local resp = string.format("<agent:choice>%s</agent:choice>", choice_res);
            
            -- If this was the turn terminator, we need to manually trigger the next model turn
            -- because the engine has already finished its 'dispatch_actions' sequence.
            if current_idx > #actions then
              local engine = require("nzi.engine.engine");
              engine.run_loop(resp, "ask", false);
            else
              table.insert(accumulated_responses, resp);
              run_others(idx + 1);
            end
          end
        end);
      end);
    else
      run_others(idx + 1);
    end
  end

  run_others(1);
end

--- Run automated tests and return failure output
function M.verify_state(callback, custom_cmd)
  local test_cmd = custom_cmd or config.options.auto_test;
  if not test_cmd then callback(nil); return end
  modal.write("Running test: " .. test_cmd, "system", false);
  local test_output = vim.fn.systemlist(test_cmd);
  local exit_code = vim.v.shell_error;
  if exit_code ~= 0 then
    local failure_text = table.concat(test_output, "\n");
    modal.write("Test failure detected.", "error", false);
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
    modal.write("Tests passed.", "system", false);
    callback(nil);
  end
end

return M;
