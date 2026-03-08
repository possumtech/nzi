local config = require("nzi.core.config");
local protocol = require("nzi.dom.parser");
local M = {};

-- UI State mapping (NOT session state)
-- Map of original buffer IDs to metadata (sugg_buf, tab_id)
-- This is now just a CACHE for open windows, not the source of truth for "pending"
M.active_views = {};

--- Derive pending changes from XML history
--- @return table: { edits = table, creations = table, deletions = table }
function M.get_pending_from_xml()
  local history = require("nzi.dom.session");
  -- IMPORTANT: We use the local cache directly. Calling format() can trigger a synchronous RPC
  -- call, which is catastrophic if called during a statusline redraw (E565).
  local xml = history.cache_xml or "";
  if xml == "" then return { edits = {}, creations = {}, deletions = {} }; end

  -- 1. Find all proposed actions
  local edits = protocol.xpath(xml, "//edit | //replace_all");
  local creations = protocol.xpath(xml, "//create");
  local deletions = protocol.xpath(xml, "//delete");
  
  -- 2. Find all resolutions
  local acks = protocol.xpath(xml, "//ack");
  local rejections = protocol.xpath(xml, "//status[@status='denied']");
  
  -- 3. Match resolutions to actions
  -- Strategy: Create a list of all potential actions and all resolutions.
  -- Since our protocol is sequential, resolutions should resolve the *earliest* matching action.
  
  local all_actions = {};
  for _, e in ipairs(edits) do table.insert(all_actions, { type = "edit", xml = e, file = protocol.get_attr(e, "file") }) end
  for _, c in ipairs(creations) do table.insert(all_actions, { type = "create", xml = c, file = protocol.get_attr(c, "file") }) end
  for _, d in ipairs(deletions) do table.insert(all_actions, { type = "delete", xml = d, file = protocol.get_attr(d, "file") }) end
  
  -- Sort by document order (heuristic: lxml returns in order of appearance)
  
  local all_resolutions = {};
  for _, a in ipairs(acks) do table.insert(all_resolutions, { type = "ack", xml = a, file = protocol.get_attr(a, "file") }) end
  for _, r in ipairs(rejections) do table.insert(all_resolutions, { type = "rej", xml = r, file = protocol.get_attr(r, "file") }) end
  
  -- 4. Cross-reference
  local resolved_indices = {};
  for _, res in ipairs(all_resolutions) do
    for i, act in ipairs(all_actions) do
      if not resolved_indices[i] then
        -- Match by file if available, otherwise just by order (if resolution has no file)
        local file_match = (not res.file or not act.file or res.file == act.file);
        if file_match then
          resolved_indices[i] = true;
          break;
        end
      end
    end
  end
  
  local pending = { edits = {}, creations = {}, deletions = {} };
  for i, act in ipairs(all_actions) do
    if not resolved_indices[i] then
      if act.type == "edit" then table.insert(pending.edits, act.xml)
      elseif act.type == "create" then table.insert(pending.creations, act.xml)
      elseif act.type == "delete" then table.insert(pending.deletions, act.xml)
      end
    end
  end
  
  return pending;
end

--- Re-sync the UI windows with the XML state
function M.rehydrate()
  local pending = M.get_pending_from_xml();
  -- For each pending edit, if we don't have a view open, open one.
  -- (Implementation of opening windows based on XML strings...)
end

--- Apply a change immediately (for YOLO mode)
--- @param bufnr number
--- @param new_lines table
function M.apply_immediately(bufnr, new_lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines);
  -- If it's a real file, save it
  local name = vim.api.nvim_buf_get_name(bufnr);
  if name ~= "" and vim.fn.filereadable(name) == 1 then
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write!") end);
  end
end

--- Open a diff view from a raw string result
--- @param bufnr number
--- @param result string
function M.open_diff(bufnr, result)
  local config = require("nzi.core.config");
  local lines = vim.split(result, "\n");
  if config.options.yolo then
    M.apply_immediately(bufnr, lines);
  else
    M.propose_edit(bufnr, lines);
  end
end

--- Propose an edit by creating a diff view
--- @param bufnr number: The original buffer
--- @param new_lines table: The lines after surgical application
function M.propose_edit(bufnr, new_lines)
  local name = vim.api.nvim_buf_get_name(bufnr);
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr });
  local existing = M.active_views[bufnr];
  
  if existing then
    -- Reuse existing suggestion buffer
    if vim.api.nvim_buf_is_valid(existing.suggestion_buf) then
      vim.api.nvim_buf_set_lines(existing.suggestion_buf, 0, -1, false, new_lines);
      config.notify("Updated existing diff for " .. vim.fn.fnamemodify(name, ":."), vim.log.levels.INFO);
      return;
    else
      -- Stale cache, clean it up
      M.active_views[bufnr] = nil;
    end
  end

  -- Create a scratch buffer for the suggestion
  local suggestion_buf = vim.api.nvim_create_buf(false, true);
  local sugg_name = name .. " (AI Suggestion)";
  
  -- If buffer name already exists (rare collision), try to find/delete it or use a unique name
  local old_sugg = vim.fn.bufnr(sugg_name);
  if old_sugg ~= -1 then
    vim.api.nvim_buf_delete(old_sugg, { force = true });
  end

  vim.api.nvim_buf_set_name(suggestion_buf, sugg_name);
  vim.api.nvim_set_option_value("filetype", ft, { buf = suggestion_buf });
  vim.api.nvim_buf_set_lines(suggestion_buf, 0, -1, false, new_lines);
  
  -- Use native Neovim tabs/windows for the diff
  vim.cmd("tab split");
  local tab_id = vim.api.nvim_get_current_tabpage();
  local win_orig = vim.api.nvim_get_current_win();
  vim.api.nvim_win_set_buf(win_orig, bufnr);
  
  vim.cmd("vsplit");
  local win_sugg = vim.api.nvim_get_current_win();
  vim.api.nvim_win_set_buf(win_sugg, suggestion_buf);
  
  -- MUST set diff mode in BOTH windows
  vim.api.nvim_win_call(win_orig, function() vim.cmd("diffthis") end);
  vim.api.nvim_win_call(win_sugg, function() vim.cmd("diffthis") end);
  
  -- Focus the original buffer so user can use 'do' (diff obtain) to pull from suggestion
  vim.api.nvim_set_current_win(win_orig);
  
  M.active_views[bufnr] = { 
    suggestion_buf = suggestion_buf,
    tab_id = tab_id
  };

  config.notify("Diff mode active. Use 'do'/'dp' to merge. Close tab when finished.", vim.log.levels.INFO);
end

--- Propose a file deletion for diff
--- @param file_path string: The file to delete
function M.propose_deletion(file_path)
  -- In XML-driven model, we don't need a local table. 
  -- The presence of <delete> without <ack> IS the proposal.
  config.notify("Marked for deletion: " .. file_path .. ". Use AI/accept to confirm.", vim.log.levels.WARN);
end

--- Find the original buffer ID if given a suggestion buffer ID
--- @param bufnr number
--- @return number|nil
function M.find_original_buffer(bufnr)
  if M.active_views[bufnr] then return bufnr end
  for orig_buf, diff in pairs(M.active_views) do
    if diff.suggestion_buf == bufnr then
      return orig_buf;
    end
  end
  return nil;
end

--- Finalize the diff (Accept the current state of original buffer)
function M.accept(bufnr)
  local actual_buf = M.find_original_buffer(bufnr);
  local config = require("nzi.core.config");
  local queue = require("nzi.core.queue");
  local engine = require("nzi.service.llm.bridge");

  if not actual_buf then
    -- Check for deletions in XML
    local name = vim.api.nvim_buf_get_name(bufnr);
    local relative_name = vim.fn.fnamemodify(name, ":.");
    local pending = M.get_pending_from_xml();
    local is_pending_deletion = false;
    for _, del_xml in ipairs(pending.deletions) do
      if protocol.get_attr(del_xml, "file") == relative_name then
        is_pending_deletion = true;
        break;
      end
    end

    if is_pending_deletion then
      config.log(relative_name, "DIFF:DELETE");
      os.remove(vim.fn.getcwd() .. "/" .. relative_name);
      vim.api.nvim_buf_delete(bufnr, { force = true });
      config.notify("File deleted: " .. relative_name, vim.log.levels.INFO);
      -- RESOLVE in XML via history
      require("nzi.dom.session").add("ask", string.format("<ack tool='delete' file='%s' status='success'>User confirmed deletion.</ack>", relative_name), nil);
      return;
    end
    config.notify("No pending diff for this buffer.", vim.log.levels.WARN);
    return;
  end

  -- SAVE THE BUFFER (User requested)
  local name = vim.api.nvim_buf_get_name(actual_buf);
  local relative_name = vim.fn.fnamemodify(name, ":.");
  config.log(relative_name, "DIFF:ACCEPT");
  if name ~= "" and vim.api.nvim_buf_is_valid(actual_buf) then
    vim.api.nvim_buf_call(actual_buf, function() 
      vim.cmd("silent! write!");
    end);
  end

  M.cleanup(actual_buf);
  config.notify("Edit diff finalized and saved.", vim.log.levels.INFO);

  -- RESOLVE in XML
  require("nzi.dom.session").add("ask", string.format("<ack status='success' tool='edit' file='%s'>User accepted and saved changes.</ack>", relative_name), nil);

  -- AUTO-DRAIN QUEUE: If turns were blocked by this diff, try to resume
  vim.schedule(function()
    if not queue.is_blocked() and not engine.is_busy then
      local next_work = queue.pop_instruction();
      if next_work then
        engine.run_loop(next_work.instruction, next_work.type, false, next_work.target_file, next_work.selection);
      end
    end
  end);
end

--- Finalize and discard (Revert original buffer? Or just close suggestion?)
function M.reject(bufnr)
  local actual_buf = M.find_original_buffer(bufnr);
  local config = require("nzi.core.config");
  local queue = require("nzi.core.queue");
  local engine = require("nzi.service.llm.bridge");

  if not actual_buf then
    local name = vim.api.nvim_buf_get_name(bufnr);
    local relative_name = vim.fn.fnamemodify(name, ":.");
    local pending = M.get_pending_from_xml();
    local is_pending_deletion = false;
    for _, del_xml in ipairs(pending.deletions) do
      if protocol.get_attr(del_xml, "file") == relative_name then
        is_pending_deletion = true;
        break;
      end
    end

    if is_pending_deletion then
      config.log(relative_name, "DIFF:REJECT_DELETE");
      config.notify("Deletion rejected: " .. relative_name, vim.log.levels.INFO);
      -- RESOLVE in XML
      require("nzi.dom.session").add("ask", string.format("<status tool='delete' file='%s' status='denied'>User rejected deletion.</status>", relative_name), nil);
      return;
    end
    config.notify("No pending diff for this buffer.", vim.log.levels.WARN);
    return;
  end

  local name = vim.api.nvim_buf_get_name(actual_buf);
  local relative_name = vim.fn.fnamemodify(name, ":.");
  config.log(relative_name, "DIFF:REJECT");

  M.cleanup(actual_buf);
  config.notify("Suggestion discarded.", vim.log.levels.INFO);

  -- RESOLVE in XML
  require("nzi.dom.session").add("ask", string.format("<status status='denied' tool='edit' file='%s'>User rejected the proposed changes.</status>", relative_name), nil);

  -- AUTO-DRAIN QUEUE
  vim.schedule(function()
    if not queue.is_blocked() and not engine.is_busy then
      local next_work = queue.pop_instruction();
      if next_work then
        engine.run_loop(next_work.instruction, next_work.type, false, next_work.target_file, next_work.selection);
      end
    end
  end);
end

--- Cleanup diff state and close suggest buffer
function M.cleanup(bufnr)
  local diff_cache = M.active_views[bufnr];
  if not diff_cache then return end

  local sugg_buf = diff_cache.suggestion_buf;
  local tab_id = diff_cache.tab_id;
  
  M.active_views[bufnr] = nil;

  if sugg_buf and vim.api.nvim_buf_is_valid(sugg_buf) then
    vim.api.nvim_buf_delete(sugg_buf, { force = true });
  end
  
  if tab_id and vim.api.nvim_tabpage_is_valid(tab_id) then
    vim.api.nvim_set_current_tabpage(tab_id);
    vim.cmd("tabclose");
  end

  -- Turn off diff mode in all windows showing this buffer if any are left
  if vim.api.nvim_buf_is_valid(bufnr) then
    local wins = vim.fn.win_findbuf(bufnr);
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function() vim.cmd("diffoff") end);
      end
    end
  end
end

function M.get_count()
  local pending = M.get_pending_from_xml();
  return #pending.edits + #pending.creations + #pending.deletions;
end

function M.has_pending_diff_for_file(relative_name)
  local pending = M.get_pending_from_xml();
  
  local config = require("nzi.core.config");
  config.log("Checking pending for: " .. relative_name, "DIFF")

  -- Function to check if any XML string in a list matches our file
  local function matches(list)
    for _, xml in ipairs(list) do
      local f = protocol.get_attr(xml, "file");
      config.log("Found pending file in XML: " .. tostring(f), "DIFF")
      if f == relative_name then return true end
    end
    return false;
  end

  return matches(pending.edits) or matches(pending.creations) or matches(pending.deletions);
end

function M.has_pending_diff(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr);
  local relative_name = vim.fn.fnamemodify(name, ":.");
  return M.has_pending_diff_for_file(relative_name);
end
return M;
