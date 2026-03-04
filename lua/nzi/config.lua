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
    },
    qwenzel = {
      model = "qwenzel:latest",
      api_base = "http://localhost:11434/v1",
      api_key = "ollama",
    },
    default = {
      model = "gpt-4-turbo",
      api_base = "https://api.openai.com/v1",
      api_key = vim.env.OPENAI_API_KEY,
    },
  },

  -- Advanced Model Options (OpenAI Spec)
  model_options = {
    temperature = 0.7,
    top_p = 1.0,
    max_tokens = 4096,
  },
  
  -- Modal window configuration
  modal = {
    border = "rounded",
    width = 80,
    height = 20,
    show_context = true, -- Whether to show system prompt and context in the modal
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
  local alias = M.options.active_model or "qwenzel";
  return M.options.models[alias] or M.options.models["qwenzel"];
end

return M;
