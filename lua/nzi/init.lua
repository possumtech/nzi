local config = require("nzi.core.config");
local buffers = require("nzi.ui.buffers");
local engine = require("nzi.engine.engine");
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
    "next", "prev", "yolo", "ralph", "accept", "reject", "reset"
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
      require("nzi.tools.shell").run(shell_cmd, bufnr, cursor[1], false);
      return;
    end

    -- 3. Handle direct command-line prompts (AI? or AI:)
    if args ~= "" then
      local first_char = args:sub(1,1);
      local instruction = args;
      local type = "question";
      if first_char == "?" or first_char == ":" then
        instruction = args:sub(2):gsub("^%s*", "");
        if first_char == ":" then type = "directive" end
      end
      
      if line1 ~= line2 or (opts.range > 0) then
        local selection = engine.get_visual_selection();
        local target_file = (type == "directive") and selection.file or nil;
        engine.run_loop(instruction, type, true, target_file, selection);
        return;
      end

      if type == "directive" then
        engine.run_loop(instruction, "directive", true, vim.fn.fnamemodify(0, ":."));
      else
        engine.handle_question(instruction, true);
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

  -- Leader Keymaps
  vim.keymap.set("n", "<leader>au", function() vim.cmd("AI/undo") end, { desc = "AI: Undo last turn" });
  vim.keymap.set("n", "<leader>an", function() vim.cmd("AI/next") end, { desc = "AI: Next pending review" });
  vim.keymap.set("n", "<leader>ap", function() vim.cmd("AI/prev") end, { desc = "AI: Prev pending review" });
  vim.keymap.set("n", "<leader>aD", function() vim.cmd("AI/accept") end, { desc = "AI: Accept current review" });
  vim.keymap.set("n", "<leader>ad", function() vim.cmd("AI/reject") end, { desc = "AI: Reject current review" });

  vim.keymap.set("n", "<leader>ax", function() vim.cmd("AI/stop") end, { desc = "AI: Abort generation" });
  vim.keymap.set("n", "<leader>aX", function() 
    vim.cmd("AI/stop");
    vim.cmd("AI/reset");
  end, { desc = "AI: Abort and Reset session" });

  vim.keymap.set("n", "<leader>ak", function() 
    local current_file = vim.fn.expand("%:.")
    vim.ui.input({ prompt = "Test args: ", default = current_file }, function(input)
      vim.cmd("AI/test " .. (input or ""))
    end)
  end, { desc = "AI: Run project tests" });

  vim.keymap.set("n", "<leader>aK", function() 
    local current_file = vim.fn.expand("%:.")
    vim.ui.input({ prompt = "Ralph args: ", default = current_file }, function(input)
      vim.cmd("AI/ralph " .. (input or ""))
    end)
  end, { desc = "AI: Run Ralph-style tests" });

  vim.keymap.set("n", "<leader>ay", function() vim.cmd("AI/yank") end, { desc = "AI: Yank last response" });
  vim.keymap.set("v", "<leader>aa", function() engine.handle_visual() end, { desc = "AI: Execute selection" });
  
  vim.keymap.set("n", "<leader>aY", function() 
    config.options.yolo = not config.options.yolo;
    local mode = config.options.yolo and "ACTIVE" or "OFF";
    vim.notify("AI: YOLO Mode is now " .. mode, vim.log.levels.WARN);
  end, { desc = "AI: Toggle YOLO mode" });

end

return M;
