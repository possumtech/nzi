local tools = require("nzi.tools");
local resolver = require("nzi.resolver");
local protocol = require("nzi.protocol");
local modal = require("nzi.modal");
local config = require("nzi.config");
local context = require("nzi.context");

local M = {};

--- Dispatch a set of model actions and return the combined agent responses
--- @param actions table: Array of parsed actions from protocol.lua
--- @param callback function: Called with combined response string
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
          -- set_state("map") handles the safe-closing logic
          context.set_state(file, "map");
          table.insert(accumulated_responses, "<agent:status>File dropped to project map.</agent:status>");
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
      -- Unknown or unimplemented tool
      run_next();
    end
  end

  run_next();
end

--- Run automated tests and return failure output if necessary
--- @param callback function: Called with test failure text or nil if success
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
