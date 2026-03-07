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
      if internal_commands[subcommand] or (line1 == line2 and opts.range <= 0) then
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

  -- Leader Keymaps
  vim.keymap.set("n", "<leader>au", function() vim.cmd("AI/undo") end, { desc = "AI: Undo last turn" });
  vim.keymap.set("n", "<leader>an", function() vim.cmd("AI/next") end, { desc = "AI: Next pending diff" });
  vim.keymap.set("n", "<leader>ap", function() vim.cmd("AI/prev") end, { desc = "AI: Prev pending diff" });
  vim.keymap.set("n", "<leader>aD", function() vim.cmd("AI/accept") end, { desc = "AI: Accept current diff" });
  vim.keymap.set("n", "<leader>ad", function() vim.cmd("AI/reject") end, { desc = "AI: Reject current diff" });

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

  -- The Four Interaction Mode Keybindings
  local function prompt_mode(prefix, prompt)
    return function()
      local cmd = "AI" .. prefix .. " "
      local mode = vim.fn.mode()
      if mode:match("[vV\22]") then
        -- Exit visual mode, then feed keys to trigger range command
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
        vim.api.nvim_feedkeys(":'<,'>" .. cmd, "n", false)
      else
        -- Prompt for input in normal mode
        vim.ui.input({ prompt = prompt .. ": " }, function(input)
          if input and input ~= "" then vim.cmd(cmd .. input) end
        end)
      end
    end
  end

  vim.keymap.set({ "n", "v" }, "<leader>a:", prompt_mode(":", "Instruct"), { desc = "AI: Instruct" });
  vim.keymap.set({ "n", "v" }, "<leader>a?", prompt_mode("?", "Ask"), { desc = "AI: Ask" });
  vim.keymap.set({ "n", "v" }, "<leader>a!", prompt_mode("!", "Run"), { desc = "AI: Run" });
  vim.keymap.set({ "n", "v" }, "<leader>a/", prompt_mode("/", "Internal"), { desc = "AI: Internal" });

  vim.keymap.set("n", "<leader>ay", function() vim.cmd("AI/yank") end, { desc = "AI: Yank last response" });
  vim.keymap.set("n", "<leader>as", function() 
    vim.ui.input({ prompt = "Session Name: ", default = "default" }, function(input)
      if input then vim.cmd("AI/save " .. input) end
    end)
  end, { desc = "AI: Save Session" });
  vim.keymap.set("n", "<leader>al", function() 
    vim.ui.input({ prompt = "Session Name: ", default = "default" }, function(input)
      if input then vim.cmd("AI/load " .. input) end
    end)
  end, { desc = "AI: Load Session" });
  vim.keymap.set("n", "<leader>aa", function() vim.cmd("AI/toggle") end, { desc = "AI: Toggle Modal" });

  -- Handle Execute selection (Visual mode shortcut)
  vim.keymap.set("v", "<leader>av", function()
    local selection = engine.get_visual_selection();
    vim.ui.input({ prompt = "AI Ask on selection: " }, function(input)
      if input and input ~= "" then
        engine.run_loop(input, "ask", false, nil, selection);
      end
    end);
  end, { desc = "AI: Ask on selection" });

  -- Context State Keymaps
  vim.keymap.set("n", "<leader>aA", function() vim.cmd("AI/active") end, { desc = "AI: Mark buffer as Active" });
  vim.keymap.set("n", "<leader>aR", function() vim.cmd("AI/read") end, { desc = "AI: Mark buffer as Read-only Context" });
  vim.keymap.set("n", "<leader>aI", function() vim.cmd("AI/ignore") end, { desc = "AI: Mark buffer as Ignored" });
  
  vim.keymap.set("n", "<leader>aY", function() 
    config.options.yolo = not config.options.yolo;
    local mode = config.options.yolo and "ACTIVE" or "OFF";
    config.notify("YOLO Mode is now " .. mode, vim.log.levels.WARN);
  end, { desc = "AI: Toggle YOLO mode" });

end

return M;
