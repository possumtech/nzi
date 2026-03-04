local M = {};

--- Default configuration options for nzi
M.defaults = {
  -- LiteLLM command (e.g., 'litellm' or a full path)
  litellm_cmd = "litellm",
  
  -- The default model to use
  default_model = "gpt-4-turbo",
  
  -- Modal window configuration
  modal = {
    border = "rounded",
    width = 80,
    height = 20,
  },
  
  -- Context management settings
  context = {
    -- Automatically ignore these filetypes or names
    ignore_filetypes = { "NvimTree", "TelescopePrompt" },
    ignore_files = { ".git", "node_modules", ".aider.tags.cache.v4" },
  },
  
  -- Fugitive integration settings
  fugitive = {
    -- Whether to automatically trigger fugitive for diffs
    auto_diff = true,
  },
};

--- Current configuration state
M.options = vim.deepcopy(M.defaults);

--- Initialize or update the configuration with user options
--- @param opts table | nil: User-provided configuration overrides
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {});
end

return M;
