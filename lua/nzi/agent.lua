local tools = require("nzi.tools");
local resolver = require("nzi.resolver");
local protocol = require("nzi.protocol");
local modal = require("nzi.modal");
local config = require("nzi.config");
local context = require("nzi.context");
local editor = require("nzi.editor");

local M = {};

--- Parse SEARCH/REPLACE blocks from a string
--- @param content string
--- @return table: Array of { search = table, replace = table }
local function parse_edit_blocks(content)
  local blocks = {};
  local lines = vim.split(content, "\n");
  local current_block = nil;
  local state = "none";

  for _, line in ipairs(lines) do
    if line:match("^<<<<<<< SEARCH") then
      current_block = { search = {}, replace = {} };
      state = "search";
    elseif line:match("^=======") then
      state = "replace";
    elseif line:match("^>>>>>>> REPLACE") then
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

    elseif action.name == "create" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local full_path = vim.fn.getcwd() .. "/" .. raw_file;
        modal.write("Creating file: " .. raw_file, "system", false);
        local ok, err = pcall(vim.fn.writefile, vim.split(action.content or "", "\n"), full_path);
        if ok then
          context.set_state(raw_file, "active");
          table.insert(accumulated_responses, "<agent:status>File created and added to context.</agent:status>");
        else
          table.insert(accumulated_responses, "<agent:status>Error creating file: " .. (err or "unknown") .. "</agent:status>");
        end
      end
      run_next();

    elseif action.name == "delete" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Deleting file: " .. file, "system", false);
          local ok = os.remove(vim.fn.getcwd() .. "/" .. file);
          if ok then
            context.set_state(file, "map"); 
            table.insert(accumulated_responses, "<agent:status>File deleted successfully.</agent:status>");
          else
            table.insert(accumulated_responses, "<agent:status>Error deleting file.</agent:status>");
          end
        else
          table.insert(accumulated_responses, string.format("<agent:status>Error resolving file for deletion: %s</agent:status>", err));
        end
      end
      run_next();

    elseif action.name == "edit" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Editing file: " .. file, "system", false);
          local bufnr = vim.fn.bufadd(file);
          vim.fn.bufload(bufnr);
          
          local blocks = parse_edit_blocks(action.content or "");
          local applied_count = 0;
          local failed_count = 0;

          for _, block in ipairs(blocks) do
            local start_line, end_line = editor.find_block(bufnr, block.search);
            if start_line then
              editor.apply(bufnr, start_line, end_line, block.replace);
              applied_count = applied_count + 1;
            else
              failed_count = failed_count + 1;
            end
          end

          if failed_count == 0 then
            table.insert(accumulated_responses, string.format("<agent:status>Applied %d edits to %s.</agent:status>", applied_count, file));
          else
            table.insert(accumulated_responses, string.format("<agent:status>Applied %d edits to %s, but %d blocks failed to match.</agent:status>", applied_count, file, failed_count));
          end
        else
          table.insert(accumulated_responses, string.format("<agent:status>Error resolving file for edit: %s</agent:status>", err));
        end
      end
      run_next();

    elseif action.name == "replace_all" then
      local raw_file = protocol.get_attr(action.attr, "file");
      if raw_file then
        local file, err = resolver.resolve(raw_file);
        if file then
          modal.write("Replacing all content: " .. file, "system", false);
          local bufnr = vim.fn.bufadd(file);
          vim.fn.bufload(bufnr);
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(action.content or "", "\n"));
          table.insert(accumulated_responses, "<agent:status>Full file replacement applied.</agent:status>");
        end
      end
      run_next();

    elseif action.name == "choice" then
      modal.write("User Choice Prompt: " .. action.content, "system", false);
      tools.choice(action.content, function(choice_res)
        vim.schedule(function()
          table.insert(accumulated_responses, string.format("<agent:choice>%s</agent:choice>", choice_res));
          run_next();
        end);
      end);
    else
      run_next();
    end
  end

  run_next();
end

--- Run automated tests and return failure output if necessary
function M.verify_state(callback)
  if not config.options.auto_test then
    callback(nil);
    return;
  end

  modal.write("Running auto-test: " .. config.options.auto_test, "system", false);
  local test_output = vim.fn.systemlist(config.options.auto_test);
  local exit_code = vim.v.shell_error;

  if exit_code ~= 0 then
    local failure_text = table.concat(test_output, "\n");
    modal.write("Test failure detected.", "error", false);
    
    local should_retry = config.options.ralph;
    if not should_retry then
      local choice = vim.fn.confirm("Test failed. Send output back to AI?", "&Yes\n&No", 1);
      should_retry = (choice == 1);
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
