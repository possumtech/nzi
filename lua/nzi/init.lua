local config = require("nzi.core.config");
local buffers = require("nzi.ui.buffers");
local engine = require("nzi.service.llm.bridge");
local modal = require("nzi.ui.modal");
local commands = require("nzi.core.commands");

local M = {};

--- Completion function for the AI command
--- @param arg_lead string: The lead string being completed
--- @param cmd_line string: The full command line
--- @return table: List of completion candidates
local function complete_ai_command(arg_lead, cmd_line)
  local subcommands = { 
    "model", "clear", "status", "buffers", "toggle", "undo", "config",
    "active", "read", "ignore", "state", "stop", "yank", "Tree", "tree",
    "next", "prev", "yolo", "ralph", "accept", "reject", "reset", "save", "load"
  };
  
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
  require("nzi.ui.visuals").setup();
  
  -- Register the primary AI command with native completion
  vim.api.nvim_create_user_command("AI", function(opts)
    opts = opts or {};
    local line1 = opts.line1 or 1;
    local line2 = opts.line2 or 1;
    local args = opts.args or "";
    local range = opts.range or 0;

    -- 1. Handle subcommands (AI/model, AI/clear, AI/status)
    if args:match("^/") then
      local cmd = args:sub(2);
      local subcommand = vim.split(cmd, " ")[1];
      local internal_commands = { 
        model = true, clear = true, undo = true, status = true, toggle = true,
        stop = true, yank = true, next = true, prev = true, accept = true,
        reject = true, yolo = true, ralph = true, reset = true, test = true,
        config = true, active = true, read = true, ignore = true, state = true,
        Tree = true, tree = true, buffers = true, save = true, load = true
      };

      -- If it's a known internal command OR no range is present, run as internal
      if internal_commands[subcommand] or (not args:match("!") and not args:match("?") and not args:match(":")) then
        commands.run(cmd);
        return;
      end
      
      -- Otherwise, if range is present, treat AI/ as a Run alias (user request)
      args = "!" .. cmd;
    end

    -- 2. Handle the "!" (Run) shortcut
    if args:match("^!") then
      local shell_cmd = args:sub(2):gsub("^%s*", "");
      local bufnr = vim.api.nvim_get_current_buf();
      
      -- Range Logic: selection as argument
      if line1 ~= line2 or (opts.range > 0) then
        local lines = vim.api.nvim_buf_get_lines(bufnr, line1-1, line2, false);
        local selection_text = table.concat(lines, " ");
        if shell_cmd == "" then
          shell_cmd = selection_text;
        else
          shell_cmd = shell_cmd .. " " .. selection_text;
        end
      end

      if shell_cmd ~= "" then
        config.log(shell_cmd, "RUN");
        require("nzi.service.vim.effector").run_shell(shell_cmd, bufnr, line1, false);
      else
        vim.notify("AI!: No command provided.", vim.log.levels.WARN);
      end
      return;
    end

    -- 3. Handle direct command-line prompts (AI? or AI:)
    if args ~= "" then
      local first_char = args:sub(1,1);
      local instruction = args;
      local type = "ask";
      if first_char == "?" or first_char == ":" then
        instruction = args:sub(2):gsub("^%s*", "");
        if first_char == ":" then type = "instruct" end
      end
      
      if line1 ~= line2 or (opts.range > 0) then
        local selection = engine.get_visual_selection();
        local target_file = (type == "instruct") and selection.file or nil;
        engine.run_loop(instruction, type, true, target_file, selection);
        return;
      end

      if type == "instruct" then
        local cur_file = vim.api.nvim_buf_get_name(0);
        local relative_file = vim.fn.fnamemodify(cur_file, ":.");
        engine.run_loop(instruction, "instruct", true, relative_file);
      else
        engine.run_loop(instruction, "ask", true);
      end
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

  -- Idiomatic Keymappings
  if config.options.default_mappings then
    require("nzi.core.actions").apply_default_mappings();
  end

  -- Interpolation: Trigger on save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("nzi_interpolation", { clear = true }),
    callback = function()
      -- Scan buffer for AI prefixes
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false);
      local parser = require("nzi.dom.parser");
      local row, type, content = parser.find_in_lines(lines);
      if type then
        engine.execute_range(row, row);
      end
    end
  });
end

return M;
