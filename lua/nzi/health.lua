local health = vim.health or require("health");

local M = {};

function M.check()
  health.start("nzi: Neovim-Native Agentic Zone Integration");

  -- Check Neovim version
  if vim.fn.has("nvim-0.10.0") == 1 then
    health.ok("Neovim 0.10+ detected (Required for vim.system)");
  else
    health.error("Neovim 0.10+ required. You are running " .. vim.version().major .. "." .. vim.version().minor);
  end

  -- Check Dependencies
  if pcall(require, "plenary") then
    health.ok("plenary.nvim found");
  else
    health.error("plenary.nvim not found. Required for async jobs and tests.");
  end

  if vim.fn.exists(":G") == 2 then
    health.ok("vim-fugitive found (Required for diff/merge workflow)");
  else
    health.warn("vim-fugitive not found. Recommended for the best diff experience.");
  end

  -- Check LiteLLM (or the configured CLI)
  local config = require("nzi.config");
  local litellm_cmd = config.options.litellm_cmd;
  if vim.fn.executable(litellm_cmd) == 1 then
    health.ok(string.format("Model CLI executable '%s' found", litellm_cmd));
  else
    health.error(string.format("Model CLI executable '%s' not found in PATH.", litellm_cmd));
    health.info("Install LiteLLM with: pip install litellm");
  end
end

return M;
