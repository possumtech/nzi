local M = {};

-- Determine default python path
local python_cmd = "python3";
local venv_path = vim.fn.getcwd() .. "/.venv/bin/python";
if vim.fn.executable(venv_path) == 1 then
  python_cmd = venv_path;
end

--- Default configuration options for nzi
M.defaults = {
  -- Command to execute for model completion
  model_cmd = { python_cmd, vim.fn.getcwd() .. "/scripts/complete.py" },
  
  -- The default model to use
  default_model = "gpt-4-turbo",
  
  -- The API base URL (for local models like Ollama)
  api_base = nil,
  
  -- API Key if needed
  api_key = nil,
  
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
