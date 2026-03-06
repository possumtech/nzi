-- lua/nzi/visuals.lua
local config = require("nzi.core.config");
local M = {};

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
  end

  define_hls();
  
  -- Ensure highlights persist across colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NziVisuals", { clear = true }),
    callback = define_hls,
  });
end

--- Get the raw status data for plugin integration
--- @return table: { text = string, hl = string }
function M.get_status_data()
  local context = require("nzi.context.context");
  local bufnr = vim.api.nvim_get_current_buf();
  
  if not context.is_real_buffer(bufnr) then 
    return { text = "", hl = "" }; 
  end
  
  local diff = require("nzi.ui.diff");
  if diff.has_pending_diff(bufnr) then
    return { text = "[AI:DIFF]", hl = "NziStatusDiff" };
  end

  local state = context.get_state(bufnr);
  if state == "active" then return { text = "[AI:A]", hl = "NziStatusActive" }; end
  if state == "read"   then return { text = "[AI:R]", hl = "NziStatusRead" }; end
  if state == "ignore" then return { text = "[AI:I]", hl = "NziStatusIgnore" }; end
  
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
