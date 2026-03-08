local config = require("nzi.core.config");
local engine = require("nzi.service.llm.bridge");

local M = {};

--- Helper to prompt for input and run a mission
--- @param prefix string: ":" for instruct, "?" for ask, etc.
--- @param prompt_label string: Label for the input prompt
local function prompt_mission(prefix, prompt_label)
  local cmd = "AI " .. prefix .. " "
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    -- Exit visual mode, then feed keys to trigger range command
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    vim.api.nvim_feedkeys(":'<,'>" .. cmd, "n", false)
  else
    -- Prompt for input in normal mode
    vim.ui.input({ prompt = prompt_label .. ": " }, function(input)
      if input and input ~= "" then vim.cmd(cmd .. input) end
    end)
  end
end

local commands = require("nzi.core.commands");

-- Core Interaction Missions
function M.instruct() prompt_mission(":", "Instruct") end
function M.ask() prompt_mission("?", "Ask") end
function M.run() prompt_mission("!", "Run") end
function M.internal() prompt_mission("/", "Internal") end

-- Session Control
function M.toggle_modal() commands.actions.toggle() end
function M.undo() commands.actions.undo() end
function M.stop() commands.actions.stop() end
function M.reset() 
  commands.actions.stop()
  commands.actions.clear() -- reset was mostly clear
end

-- Diff Management
function M.next_diff() vim.cmd("AI/next") end
function M.prev_diff() vim.cmd("AI/prev") end
function M.accept_diff() vim.cmd("AI/accept") end
function M.reject_diff() vim.cmd("AI/reject") end

-- Context Management
function M.mark_active() vim.cmd("AI/active") end
function M.mark_read_only() vim.cmd("AI/read") end
function M.mark_ignored() vim.cmd("AI/ignore") end

-- Persistence
function M.save_session()
  vim.ui.input({ prompt = "Session Name: ", default = "default" }, function(input)
    if input then commands.actions.save(input) end
  end)
end

function M.load_session()
  vim.ui.input({ prompt = "Session Name: ", default = "default" }, function(input)
    if input then commands.actions.load(input) end
  end)
end

-- Utilities
function M.yank_last_response() vim.cmd("AI/yank") end

function M.run_tests()
  local current_file = vim.fn.expand("%:.")
  vim.ui.input({ prompt = "Test args: ", default = current_file }, function(input)
    commands.actions.test(input or "")
  end)
end

function M.run_ralph()
  local current_file = vim.fn.expand("%:.")
  vim.ui.input({ prompt = "Ralph args: ", default = current_file }, function(input)
    vim.cmd("AI/ralph " .. (input or ""))
  end)
end

function M.toggle_yolo()
  config.options.yolo = not config.options.yolo;
  local mode = config.options.yolo and "ACTIVE" or "OFF";
  config.notify("YOLO Mode is now " .. mode, vim.log.levels.WARN);
end

--- Apply the standard leader mappings
function M.apply_default_mappings()
  local maps = {
    { mode = "n", key = "<leader>au", action = M.undo, desc = "AI: Undo last turn" },
    { mode = "n", key = "<leader>an", action = M.next_diff, desc = "AI: Next pending diff" },
    { mode = "n", key = "<leader>ap", action = M.prev_diff, desc = "AI: Prev pending diff" },
    { mode = "n", key = "<leader>aD", action = M.accept_diff, desc = "AI: Accept current diff" },
    { mode = "n", key = "<leader>ad", action = M.reject_diff, desc = "AI: Reject current diff" },
    { mode = "n", key = "<leader>ax", action = M.stop, desc = "AI: Abort generation" },
    { mode = "n", key = "<leader>aX", action = M.reset, desc = "AI: Abort and Reset session" },
    { mode = "n", key = "<leader>ak", action = M.run_tests, desc = "AI: Run project tests" },
    { mode = "n", key = "<leader>aK", action = M.run_ralph, desc = "AI: Run Ralph-style tests" },
    { mode = { "n", "v" }, key = "<leader>a:", action = M.instruct, desc = "AI: Instruct" },
    { mode = { "n", "v" }, key = "<leader>a?", action = M.ask, desc = "AI: Ask" },
    { mode = { "n", "v" }, key = "<leader>a!", action = M.run, desc = "AI: Run" },
    { mode = { "n", "v" }, key = "<leader>a/", action = M.internal, desc = "AI: Internal" },
    { mode = "n", key = "<leader>ay", action = M.yank_last_response, desc = "AI: Yank last response" },
    { mode = "n", key = "<leader>as", action = M.save_session, desc = "AI: Save Session" },
    { mode = "n", key = "<leader>al", action = M.load_session, desc = "AI: Load Session" },
    { mode = "n", key = "<leader>aa", action = M.toggle_modal, desc = "AI: Toggle Modal" },
    { mode = "n", key = "<leader>aA", action = M.mark_active, desc = "AI: Mark buffer as Active" },
    { mode = "n", key = "<leader>aR", action = M.mark_read_only, desc = "AI: Mark buffer as Read-only Context" },
    { mode = "n", key = "<leader>aI", action = M.mark_ignored, desc = "AI: Mark buffer as Ignored" },
    { mode = "n", key = "<leader>aY", action = M.toggle_yolo, desc = "AI: Toggle YOLO mode" },
  }

  for _, map in ipairs(maps) do
    vim.keymap.set(map.mode, map.key, map.action, { desc = map.desc });
  end
end

return M;
