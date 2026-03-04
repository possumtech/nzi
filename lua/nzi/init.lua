local config = require("nzi.config");
local buffers = require("nzi.buffers");
local engine = require("nzi.engine");
local modal = require("nzi.modal");
local commands = require("nzi.commands");

local M = {};

--- Completion function for the AI command
--- @param arg_lead string: The lead string being completed
--- @param cmd_line string: The full command line
--- @return table: List of completion candidates
local function complete_ai_command(arg_lead, cmd_line)
  local subcommands = { "model", "clear", "status", "buffers", "toggle", "undo", "set", "add", "config" };
  
  -- If we're at the very start of the command arguments
  if arg_lead:match("^/") or (not arg_lead:match("^/") and #vim.split(cmd_line, " ") == 1) then
    local lead = arg_lead:match("^/(.*)") or arg_lead;
    local candidates = {};
    for _, sub in ipairs(subcommands) do
      if sub:sub(1, #lead) == lead then
        table.insert(candidates, "/" .. sub);
      end
    end
    return candidates;
  end

  -- Context-aware completion for model switching
  if cmd_line:match("/model%s+") then
    local model_lead = arg_lead;
    local candidates = {};
    local model_list = {};
    for alias, _ in pairs(config.options.models) do
      table.insert(model_list, alias);
    end
    table.sort(model_list);
    
    for _, alias in ipairs(model_list) do
      if alias:sub(1, #model_lead) == model_lead then
        table.insert(candidates, alias);
      end
    end
    return candidates;
  end

  return {};
end

--- Setup function for nzi plugin
--- @param opts table | nil: User-provided configuration overrides
function M.setup(opts)
  config.setup(opts);
  buffers.setup();
  
  -- Register the primary AI command with native completion
  vim.api.nvim_create_user_command("AI", function(opts)
    local line1 = opts.line1;
    local line2 = opts.line2;
    local args = opts.args or "";

    -- 1. Handle subcommands (AI/model, AI/clear, AI/status)
    if args:match("^/") then
      commands.run(args:sub(2));
      return;
    end

    -- 2. Handle the "!" shell shortcut
    if args:match("^!") then
      local shell_cmd = args:sub(2):gsub("^%s*", "");
      local bufnr = vim.api.nvim_get_current_buf();
      local cursor = vim.api.nvim_win_get_cursor(0);
      require("nzi.shell").run(shell_cmd, bufnr, cursor[1], false);
      return;
    end

    -- 3. Handle direct command-line prompts (AI? or AI:)
    if args ~= "" then
      local first_char = args:sub(1,1);
      if first_char == "?" or first_char == ":" then
        engine.handle_question(args:sub(2):gsub("^%s*", ""), true);
        return;
      end
      
      if line1 ~= line2 or (opts.range > 0) then
        engine.handle_question(args .. "\n\n### FOCUS RANGE\n" .. table.concat(vim.api.nvim_buf_get_lines(0, line1-1, line2, false), "\n"), true);
        return;
      end

      engine.handle_question(args, true);
      return;
    end

    -- 4. Fallback to range-based detection
    if line1 ~= line2 or (opts.range > 0) then
      engine.execute_range(line1, line2);
      return;
    end

    -- 5. Fallback to line parsing
    engine.execute_current_line();
  end, { 
    nargs = "*", 
    range = true, 
    complete = complete_ai_command,
    desc = "Primary Agentic Interface (AI)" 
  });

  -- Abbreviations for UX
  vim.cmd([[cnoreabbrev <expr> AI! (getcmdtype() == ':' && getcmdline() == 'AI!') ? 'AI !' : 'AI!']])
  vim.cmd([[cnoreabbrev <expr> AI? (getcmdtype() == ':' && getcmdline() == 'AI?') ? 'AI ?' : 'AI?']])
  vim.cmd([[cnoreabbrev <expr> AI: (getcmdtype() == ':' && getcmdline() == 'AI:') ? 'AI :' : 'AI:']])

end

return M;
