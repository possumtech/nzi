local M = {};

--- Default configuration options for nzi
M.defaults = {
  -- The currently active model alias
  active_model = vim.env.NZI_MODEL_ALIAS or "defaultModel",

  -- Metadata for providers like OpenRouter
  referer = vim.env.NZI_REFERER or "https://github.com/possumtech/nzi",
  title = vim.env.NZI_TITLE or "nzi",

  -- Pre-configured models with aliases
  models = {
    defaultModel = {
      provider = vim.env.NZI_PROVIDER or "openrouter",
      model = vim.env.NZI_MODEL_NAME or "deepseek/deepseek-chat",
      api_base = vim.env.NZI_API_BASE or "https://openrouter.ai/api/v1",
      api_key = vim.env.NZI_API_KEY or vim.env.OPENROUTER_API_KEY,
      role_preference = "system",
    }
  },

  -- Ecosystem settings
  python_cmd = vim.split(vim.env.NZI_PYTHON_CMD or "./.venv/bin/python3", " "), 

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
    ignore_filetypes = { "NvimTree", "TelescopePrompt", "TelescopeResults", "fzf", "qf" },
    ignore_files = {}, -- User overrides only
  },
  
  -- Visual Context settings
  visuals = {
    enabled = true, -- Highlight buffer backgrounds based on AI state
    bold = false,    -- Use more vibrant colors (set to true for high contrast)
    colors = {
      active = "#1e2a1e", -- Subtle green
      read   = "#2a241e", -- Subtle orange/brown
      ignore = "#2a1e1e", -- Subtle red
      diff   = "#1e1e2a", -- Subtle blue
    },
    bold_colors = {
      active = "#2e4a2e", -- Vibrant green
      read   = "#4a3a2e", -- Vibrant orange/brown
      ignore = "#4a2e2e", -- Vibrant red
      diff   = "#2e2e4a", -- Vibrant blue
    },
  },

  -- Agentic Loop settings
  roadmap_file = "AGENTS.md", -- Project roadmap/task list file
  prompt_file = "nzi.prompt", -- System rules file
  max_turns = 5, -- Safety cap for autonomous tool loops
  yolo = false,  -- If true, skip permission prompts for shell/env tools
  auto_test = nil, -- Command string to run after turns (e.g. "npm test")
  ralph = false,   -- If true, automatically send test failures back to model
};

M.options = M.defaults;

--- Initialize or update the configuration with user options
--- @param opts table | nil: User-provided configuration overrides
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {});
end

--- Get the current active model configuration
function M.get_active_model()
  local alias = M.options.active_model or "defaultModel";
  local model = M.options.models[alias] or M.options.models["defaultModel"];
  
  -- Fallback: If for some reason defaultModel is missing from the table, return the first available
  if not model then
    local _, first = next(M.options.models)
    return first
  end
  
  return model;
end

--- Notify the user with the active model alias as a prefix
--- @param msg string
--- @param level number | nil (default INFO)
function M.notify(msg, level)
  local alias = M.options.active_model or "AI";
  vim.notify(alias .. ": " .. msg, level or vim.log.levels.INFO);
end

--- Log a message to nzi_debug.log if debug mode is active
--- @param msg string: The message to log
--- @param category string | nil: Optional category (e.g. "USER", "UI", "CMD")
function M.log(msg, category)
  local alias = M.options.active_model or "AI";
  if os.getenv("NZI_DEBUG") == "1" then
    local log_path = vim.fn.getcwd() .. "/nzi_debug.log";
    local f = io.open(log_path, "a");
    if f then
      local tag = category and string.format("[%s] ", category) or "";
      f:write(string.format("[%s] [%s] %s%s\n", os.date("%H:%M:%S"), alias, tag, msg));
      f:close();
    end
  end
end

function M.get_plugin_path()
  local str = debug.getinfo(1, "S").source:sub(2);
  -- Path is lua/nzi/core/config.lua, we want the root
  return vim.fn.fnamemodify(str, ":h:h:h:h");
end

return M;
