local M = {};

--- Default configuration options for nzi
M.defaults = {
  -- The currently active model alias
  active_model = "coder",

  -- Pre-configured models with aliases
  models = {
    coder = {
      model = "qwen/qwen-2.5-coder-32b-instruct",
      api_base = "https://openrouter.ai/api/v1",
      api_key = vim.env.OPENROUTER_API_KEY,
      -- O1/O3 class models prefer 'developer', most others use 'system'
      role_preference = "system", 
    },
    qwenzel = {
      model = "qwenzel:latest",
      api_base = "http://localhost:11434/v1",
      api_key = "ollama",
      role_preference = "system",
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
    top_p = 1.0,
    max_tokens = 4096,
    -- Frequency and presence penalties prevent repetition
    frequency_penalty = 0.0,
    presence_penalty = 0.0,
    -- Custom stop sequences
    stop = nil,
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
