local M = {};

--- Default configuration options for nzi
M.defaults = {
  -- The currently active model alias (selected via environment)
  active_model = vim.env.NZI_MODEL or "coder",

  -- OpenRouter/OpenAI identification
  referer = vim.env.NZI_REFERER or "https://github.com/possumtech/nzi",
  title = "nzi",

  -- Pre-configured models with aliases
  models = {
    coder = {
      model = "anthropic/claude-3.5-sonnet",
      api_base = "https://openrouter.ai/api/v1",
      api_key = vim.env.OPENROUTER_API_KEY,
      role_preference = "system", 
    },
    local_coder = {
      model = "qwen2.5-coder:latest",
      api_base = "http://192.168.1.17:11434/v1",
      api_key = "ollama",
      role_preference = "developer",
    },
    default = {
      model = "gpt-4-turbo",
      api_base = "https://api.openai.com/v1",
      api_key = vim.env.OPENAI_API_KEY,
      role_preference = "system",
    },
  },

  -- Advanced Model Options (OpenAI Standard)
  model_options = {
    temperature = 0.7,
    top_p = 0.8,
    max_tokens = 4096,
    stream = true,
  },
  
  -- Modal window configuration
  modal = {
    border = "rounded",
    width = 80,
    height = 20,
    show_context = true, 
  },
  
  -- Context management settings
  context = {
    ignore_filetypes = { "NvimTree", "TelescopePrompt" },
    ignore_files = { ".git", "node_modules", ".aider.tags.cache.v4" },
  },
  
  -- Fugitive integration settings
  fugitive = {
    auto_diff = true,
  },
};

M.options = M.defaults;

--- Initialize or update the configuration with user options
--- @param opts table | nil: User-provided configuration overrides
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {});
end

--- Get the current active model configuration
function M.get_active_model()
  local alias = M.options.active_model or "coder";
  return M.options.models[alias] or M.options.models["coder"];
end

return M;
