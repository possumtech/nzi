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

  -- Check Curl (Primary for API communication)
  if vim.fn.executable("curl") == 1 then
    health.ok("curl found");
  else
    health.error("curl not found in PATH. Required for model communication.");
  end

  -- Check Python & LiteLLM
  local config = require("nzi.config");
  local python_cmd = config.options.python_cmd[1] or "python3";
  
  if vim.fn.executable(python_cmd) == 1 then
    -- Check for pip
    local pip_check = vim.system({python_cmd, "-m", "pip", "--version"}, { text = true }):wait();
    if pip_check.code == 0 then
      health.ok("Pip found via " .. python_cmd .. " -m pip");
    else
      health.warn("Pip not found in the Python environment. You may need to install 'python3-pip' or recreate your venv with 'python3 -m venv .venv'.");
    end

    -- Check for litellm module
    local job = vim.system({python_cmd, "-c", "import litellm; from litellm import completion; print('Found')"}, { text = true }):wait();
    if job.code == 0 then
      health.ok("LiteLLM found and functional");
    else
      health.error("LiteLLM not found in Python environment. Run: " .. python_cmd .. " -m pip install litellm");
    end
  else
    health.error("Python executable not found: " .. python_cmd .. ". Check NZI_PYTHON_CMD or config.python_cmd.");
  end
end

return M;
