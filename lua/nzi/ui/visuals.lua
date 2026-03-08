-- lua/nzi/ui/visuals.lua
local config = require("nzi.core.config");
local M = {};

M.anim_frame = 0;
M.anim_timer = nil;
M.is_busy = false; -- Managed by engine

local frames = { "   ", ".  ", ".. ", "...", " ..", "  ." };

--- Setup visual context highlight groups
function M.setup()
  local function define_hls()
    -- Statusline Highlights (Text + Colored BG)
    vim.api.nvim_set_hl(0, "NziStatusActive",   { fg = "#ffffff", bg = "#1b5e20", ctermfg = 15, ctermbg = 2, bold = true });
    vim.api.nvim_set_hl(0, "NziStatusRead",     { fg = "#ffffff", bg = "#e65100", ctermfg = 15, ctermbg = 3, bold = true });
    vim.api.nvim_set_hl(0, "NziStatusIgnore",   { fg = "#ffffff", bg = "#b71c1c", ctermfg = 15, ctermbg = 1, bold = true });
    vim.api.nvim_set_hl(0, "NziStatusDiff",     { fg = "#ffffff", bg = "#0d47a1", ctermfg = 15, ctermbg = 4, bold = true });
    vim.api.nvim_set_hl(0, "NziStatusThinking", { fg = "#ffffff", bg = "#fe8019", ctermfg = 15, ctermbg = 214, bold = true });
    
    vim.api.nvim_set_hl(0, "NziTelemetry", { fg = "#666666", italic = true, ctermfg = 242 });
    
    -- Section Backgrounds (Modal ONLY)
    vim.api.nvim_set_hl(0, "NziUserSection",      { bg = "#1a1a1a", ctermbg = 234 });
    vim.api.nvim_set_hl(0, "NziAssistantSection", { bg = "#161616", ctermbg = 233 });
    vim.api.nvim_set_hl(0, "NziHistorySection",   { bg = "#121212", ctermbg = 232 });
  end

  define_hls();
  
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NziVisuals", { clear = true }),
    callback = define_hls,
  });

  -- NZI Statusline Integration: Add to global statusline if not present
  local sl = vim.o.statusline;
  if not sl:match("nzi_statusline") then
    -- We append it to the right side
    if sl == "" then
      vim.o.statusline = "%f %m %= %{%v:lua.nzi_statusline()%} %l:%c %p%% ";
    else
      -- Try to insert before the right-aligned part or just append
      if sl:match("%%=") then
        vim.o.statusline = sl:gsub("%%=", "%%= %%{v:lua.nzi_statusline()%%} ");
      end
    end
  end
end

function M.set_busy(busy)
  -- Forward to thinking animation
  if busy then M.start_thinking() else M.stop_thinking() end
end

function M.start_thinking()
  if M.anim_timer then return end
  M.is_busy = true; -- Ensure get_status_data sees it
  M.anim_timer = vim.loop.new_timer();
  M.anim_timer:start(0, 250, vim.schedule_wrap(function()
    M.anim_frame = (M.anim_frame % #frames) + 1;
    M.refresh();
  end));
end

function M.stop_thinking()
  if M.anim_timer then
    M.anim_timer:stop();
    M.anim_timer:close();
    M.anim_timer = nil;
  end
  M.is_busy = false;
  M.anim_frame = 0;
  M.refresh();
end

function M.get_status_data()
  local context = require("nzi.service.vim.watcher");
  local config = require("nzi.core.config");
  local alias = config.options.active_model or "AI";
  local bufnr = vim.api.nvim_get_current_buf();
  
  if M.is_busy then
    local dots = frames[M.anim_frame] or "...";
    return { text = string.format("[%s %s]", alias, dots), hl = "NziStatusThinking" };
  end

  if not context.is_real_buffer(bufnr) then 
    return { text = "", hl = "" }; 
  end
  
  local diff = require("nzi.ui.diff");
  if diff.has_pending_diff(bufnr) then
    return { text = string.format("[%s:DIFF]", alias), hl = "NziStatusDiff" };
  end

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

function M.get_statusline()
  local ok, res = pcall(function()
    local data = M.get_status_data();
    if not data or data.text == "" then return ""; end
    return string.format("%%#%s# %s %%*", data.hl, data.text);
  end)
  if not ok then return ""; end
  return res;
end

-- EXPOSE GLOBALLY for Vim statusline (prevents E117 if require is tricky)
_G.nzi_statusline = M.get_statusline;

function M.refresh()
  vim.cmd("redrawstatus");
end

return M;
