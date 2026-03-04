local M = {};

--- Default configuration options for nzi
M.defaults = {
  -- The default model to use
  default_model = "gpt-4-turbo",
  
  -- The API base URL (Standard OpenAI endpoint)
  api_base = "https://api.openai.com/v1",
  
  -- API Key if needed (defaults to environment variable)
  api_key = vim.env.OPENAI_API_KEY,
  
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
