-- lua/nzi/visuals.lua
local config = require("nzi.core.config");
local M = {};

M.anim_frame = 0;
M.anim_timer = nil;

local frames = { "   ", ".  ", ".. ", "...", " ..", "  ." };

--- Setup visual context highlight groups
function M.setup()
  local function define_hls()
    -- Statusline segments: White text on colored backgrounds.
    -- Standard "Pro" colors for maximum legibility and professional look.
    
    -- Active: Deep Forest Green
    vim.api.nvim_set_hl(0, "NziStatusActive", { fg = "#ffffff", bg = "#1b5e20", ctermfg = 15, ctermbg = 2, bold = true });
    -- Read: Deep Burnt Orange
    vim.api.nvim_set_hl(0, "NziStatusRead",   { fg = "#ffffff", bg = "#e65100", ctermfg = 15, ctermbg = 3, bold = true });
    -- Ignore: Deep Crimson Red (They said red is fine)
    vim.api.nvim_set_hl(0, "NziStatusIgnore", { fg = "#ffffff", bg = "#b71c1c", ctermfg = 15, ctermbg = 1, bold = true });
    -- Diff: Deep Royal Blue
    vim.api.nvim_set_hl(0, "NziStatusDiff",   { fg = "#ffffff", bg = "#0d47a1", ctermfg = 15, ctermbg = 4, bold = true });
    -- Thinking: Vibrant Orange
    vim.api.nvim_set_hl(0, "NziStatusThinking", { fg = "#ffffff", bg = "#fe8019", ctermfg = 15, ctermbg = 214, bold = true });
  end

  define_hls();
  
  -- Ensure highlights persist across colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NziVisuals", { clear = true }),
    callback = define_hls,
  });
end

--- Start the thinking animation
function M.start_thinking()
  if M.anim_timer then return end
  M.anim_timer = vim.loop.new_timer();
  M.anim_timer:start(0, 250, vim.schedule_wrap(function()
    M.anim_frame = (M.anim_frame % #frames) + 1;
    M.refresh();
  end));
end

--- Stop the thinking animation
function M.stop_thinking()
  if M.anim_timer then
    M.anim_timer:stop();
    M.anim_timer:close();
    M.anim_timer = nil;
  end
  M.anim_frame = 0;
  M.refresh();
end

--- Get the raw status data for plugin integration
--- @return table: { text = string, hl = string }
function M.get_status_data()
  local context = require("nzi.context.context");
  local config = require("nzi.core.config");
  local engine = require("nzi.engine.engine");
  local alias = config.options.active_model or "AI";
  local bufnr = vim.api.nvim_get_current_buf();
  
  -- 0. Thinking state (Highest Priority)
  if engine.is_busy then
    local dots = frames[M.anim_frame] or "...";
    return { text = string.format("[%s %s]", alias, dots), hl = "NziStatusThinking" };
  end

  if not context.is_real_buffer(bufnr) then 
    return { text = "", hl = "" }; 
  end
  
  local diff = require("nzi.ui.diff");
  
  -- 1. Check if CURRENT buffer has a pending diff
  if diff.has_pending_diff(bufnr) then
    return { text = string.format("[%s:DIFF]", alias), hl = "NziStatusDiff" };
  end

  -- 2. Check if ANY OTHER buffers have pending diffs (Global indicator)
  local total_diffs = diff.get_count();
  if total_diffs > 0 then
    return { text = string.format("[%s:DIFS: %d]", alias, total_diffs), hl = "NziStatusDiff" };
  end

  local state = context.get_state(bufnr);
  if state == "active" then return { text = string.format("[%s:A]", alias), hl = "NziStatusActive" }; end
  if state == "read"   then return { text = string.format("[%s:R]", alias), hl = "NziStatusRead" }; end
  if state == "ignore" then return { text = string.format("[%s:I]", alias), hl = "NziStatusIgnore" }; end
  
  return { text = "", hl = "" };
end

--- Get the colored statusline indicator for the current buffer (Native statusline)
--- @return string
function M.get_statusline()
  local data = M.get_status_data();
  if data.text == "" then return ""; end
  
  -- Return raw highlight tags for expansion.
  return string.format("%%#%s# %s %%*", data.hl, data.text);
end

--- Refresh the statusline
function M.refresh()
  vim.cmd("redrawstatus");
end

return M;
