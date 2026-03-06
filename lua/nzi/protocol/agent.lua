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
function M.dispatch_actions(actions, callback)
  local current_idx = 1;
  local accumulated_responses = {};

  local function run_next()
    if current_idx > #actions then
      if #accumulated_responses > 0 then
        callback(table.concat(accumulated_responses, "\n\n"));
      else
        callback(nil);
      end
      return;
    end

    local action = actions[current_idx];
    current_idx = current_idx + 1;

    if action.name == "grep" then
      modal.write("Searching universe: " .. action.content, "system", false);
      local grep_res = tools.grep(action.content);
      table.insert(accumulated_responses, string.format("<agent:grep>\n%s\n</agent:grep>", grep_res));
      run_next();

    elseif action.name == "definition" then
      modal.write("LSP Lookup: " .. action.content, "system", false);
      local def_res = tools.definition(action.content);
      table.insert(accumulated_responses, string.format("<agent:status>%s</agent:status>", def_res));
      run_next();

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
      run_next();

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
      run_next();

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
      run_next();

    elseif action.name == "reset" then
      modal.write("Agent requested session reset.", "system", false);
      require("nzi.core.commands").run("reset");
      table.insert(accumulated_responses, "<agent:status>Session history and context have been reset.</agent:status>");
      run_next();

    elseif action.name == "create" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
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
            table.insert(accumulated_responses, "<agent:status>Proposed new file content. Awaiting review.</agent:status>");
          end
        else
          table.insert(accumulated_responses, "<agent:status>File creation denied by user.</agent:status>");
        end
      end
      run_next();

    elseif action.name == "delete" then
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
            table.insert(accumulated_responses, string.format("<agent:status>Proposed deletion of %s. Awaiting review.</agent:status>", file));
          end
        end
      end
      run_next();

    elseif action.name == "edit" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Analyzing edits for: " .. file, "system", false);
          local bufnr = vim.fn.bufadd(file);
          vim.fn.bufload(bufnr);
          
          local blocks = parse_edit_blocks(action.content or "");
          
          -- We apply edits to a TEMP COPY of the lines
          local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
          
          -- Helper to apply surgical blocks to a table of lines (Lua indices)
          local function apply_blocks_to_lines(lines, edit_blocks)
            local modified = false;
            for _, block in ipairs(edit_blocks) do
              -- We need a way to run find_block on raw lines...
              -- I'll refactor editor.lua to handle this or just apply to a temp buffer.
              -- Decision: Create a hidden temp buffer for the merge.
              local temp_buf = vim.api.nvim_create_buf(false, true);
              vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines);
              
              local s, e, q = editor.find_block(temp_buf, block.search);
              if s then
                editor.apply(temp_buf, s, e, block.replace);
                lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false);
                modified = true;
              end
              vim.api.nvim_buf_delete(temp_buf, { force = true });
            end
            return lines, modified;
          end

          local final_lines, was_modified = apply_blocks_to_lines(current_lines, blocks);

          if was_modified then
            if config.options.yolo then
              diff.apply_immediately(bufnr, final_lines);
              table.insert(accumulated_responses, string.format("<agent:status>Surgical edits applied to %s (YOLO).</agent:status>", file));
            else
              diff.propose_edit(bufnr, final_lines);
              table.insert(accumulated_responses, string.format("<agent:status>Proposed edits for %s. Awaiting review.</agent:status>", file));
            end
          else
            table.insert(accumulated_responses, string.format("<agent:status>Error: No blocks matched in %s. Edit aborted.</agent:status>", file));
          end
        end
      end
      run_next();

    elseif action.name == "replace_all" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          local bufnr = vim.fn.bufadd(file);
          vim.fn.bufload(bufnr);
          local lines = vim.split(action.content or "", "\n");
          if config.options.yolo then
            diff.apply_immediately(bufnr, lines);
            table.insert(accumulated_responses, string.format("<agent:status>Full replacement applied to %s (YOLO).</agent:status>", file));
          else
            diff.propose_edit(bufnr, lines);
            table.insert(accumulated_responses, string.format("<agent:status>Proposed full replacement for %s.</agent:status>", file));
          end
        end
      end
      run_next();

    elseif action.name == "choice" then
      modal.write("User Choice Prompt: " .. action.content, "system", false);
      tools.choice(action.content, function(choice_res)
        vim.schedule(function()
          if choice_res == "User cancelled selection." or choice_res:match("cancelled") then
            -- HALT SIGNAL: Return nil to callback to stop the engine loop
            callback(nil, "ABORTED");
          else
            table.insert(accumulated_responses, string.format("<agent:choice>%s</agent:choice>", choice_res));
            run_next();
          end
        end);
      end);
    else
      run_next();
    end
  end

  run_next();
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
