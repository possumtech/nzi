local config = require("nzi.config");
local buffers = require("nzi.buffers");
local engine = require("nzi.engine");
local modal = require("nzi.modal");
local commands = require("nzi.commands");

local M = {};

--- Setup function for nzi plugin
--- @param opts table | nil: User-provided configuration overrides
function M.setup(opts)
  config.setup(opts);
  buffers.setup();
  
  -- Register the primary AI command
  vim.api.nvim_create_user_command("AI", function(opts)
    local line1 = opts.line1;
    local line2 = opts.line2;
    local args = opts.args or "";

    -- 1. Handle subcommands (AI/model, AI/clear, AI/status)
    if args:match("^/") then
      commands.run(args:sub(2));
      return;
    end

    -- 2. Handle the "!" shell shortcut (e.g., :AI ! ls)
    if args:match("^!") then
      local shell_cmd = args:sub(2):gsub("^%s*", "");
      local bufnr = vim.api.nvim_get_current_buf();
      local cursor = vim.api.nvim_win_get_cursor(0);
      require("nzi.shell").run(shell_cmd, bufnr, cursor[1], false); -- false = no injection
      return;
    end

    -- 3. Handle direct command-line prompts (e.g., :AI ? hello)
    -- NOTE: Directives (:) are currently treated exactly like questions (?)
    if args ~= "" then
      local first_char = args:sub(1,1);
      if first_char == "?" or first_char == ":" then
        engine.handle_question(args:sub(2):gsub("^%s*", ""), true);
        return;
      end
      
      -- If a range was selected but no "?" or ":" prefix, treat as question for the range
      if line1 ~= line2 or (opts.range > 0) then
        engine.handle_question(args .. "\n\n### FOCUS RANGE\n" .. table.concat(vim.api.nvim_buf_get_lines(0, line1-1, line2, false), "\n"), true);
        return;
      end

      -- Default to question for raw arguments without a range
      engine.handle_question(args, true);
      return;
    end

    -- 4. Fallback to range-based interpolated directive detection
    if line1 ~= line2 or (opts.range > 0) then
      engine.execute_range(line1, line2);
      return;
    end

    -- 5. Fallback to parsing the current line in the buffer
    engine.execute_current_line();
  end, { 
    nargs = "*", 
    range = true, 
    desc = "Primary Agentic Interface (AI)" 
  });

  -- The "hacky way" to allow :AI!, :AI?, and :AI: by expanding them
  vim.cmd([[cnoreabbrev <expr> AI! (getcmdtype() == ':' && getcmdline() == 'AI!') ? 'AI !' : 'AI!']])
  vim.cmd([[cnoreabbrev <expr> AI? (getcmdtype() == ':' && getcmdline() == 'AI?') ? 'AI ?' : 'AI?']])
  vim.cmd([[cnoreabbrev <expr> AI: (getcmdtype() == ':' && getcmdline() == 'AI:') ? 'AI :' : 'AI:']])

end

return M;
