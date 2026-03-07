local assert = require("luassert")
local engine = require("nzi.engine.engine")
local prompts = require("nzi.service.llm.prompt")
local config = require("nzi.core.config")

describe("5. Engine & Prompt Construction", function()
  before_each(function()
    require("nzi.dom.session").clear()
  end)

  it("should extract next pending task from AGENTS.md", function()
    -- mock gather
    local orig_gather = prompts.gather
    prompts.gather = function()
      return {
        project = "Some project info\n- [x] Done task\n- [ ] Pending task 1\n- [ ] Pending task 2",
        next_task_suggest = "Pending task 1"
      }
    end

    local messages, system, ctx, ctx_list = prompts.build_messages("test", "instruct", "test.lua", false, nil)
    
    local user_msg = messages[#messages].content
    assert.match("Pending task 1", user_msg)
    
    prompts.gather = orig_gather
  end)

  it("should wrap visual selection metadata correctly in <agent:selection>", function()
    local selection = {
      file = "test.lua",
      start_line = 10,
      start_col = 5,
      end_line = 12,
      end_col = 15,
      mode = "v",
      text = "local x = 5"
    }

    local messages = prompts.build_messages("explain this", "ask", nil, false, selection)
    local user_msg = messages[#messages].content
    
    assert.match("<agent:selection file=\"test.lua\" start=\"10:5\" end=\"12:15\">", user_msg)
    assert.match("local x = 5", user_msg)
  end)

  it("smart_filter should escape conflicting XML but leave code readable", function()
    local code = "if a < b then print('ok') end"
    local filtered = prompts.smart_filter(code)
    
    -- It SHOULD escape the < in code if it's followed by a space to prevent XML confusion
    assert.equals("if a &lt; b then print('ok') end", filtered)

    local conflicting = "<model:read file='foo' />"
    local filtered_conflicting = prompts.smart_filter(conflicting)
    
    -- It SHOULD escape our reserved namespaces
    assert.match("&lt;model:read file='foo' /&gt;", filtered_conflicting)
  end)

  it("should respect max_turns cap", function()
    config.options.max_turns = 1
    
    -- Mock job to always return an action that causes a recursive loop
    local job = require("nzi.service.llm.job")
    local orig_run = job.run
    
    local call_count = 0
    job.run = function(messages, callback, on_stdout)
      call_count = call_count + 1
      -- Return a choice action to force another turn
      on_stdout("<model:choice>continue?</model:choice>", "content")
      callback(true, "<model:choice>continue?</model:choice>")
      return { kill = function() end }
    end
    
    -- Mock tools.choice so it doesn't block
    local tools = require("nzi.tools.tools")
    local orig_choice = tools.choice
    tools.choice = function(msg, cb)
      cb("yes")
    end

    engine.run_loop("start", "ask", false, nil)
    
    -- Allow the scheduled tasks to run
    vim.wait(1000, function() return not engine.is_busy end)
    
    -- Call count should be max_turns + 1 (the one that hits the cap and stops)
    -- Actually, run_loop increments before checking.
    assert.True(call_count <= 2, "Loop should halt at max_turns")
    
    -- restore
    job.run = orig_run
    tools.choice = orig_choice
  end)

  it("should nest <agent:selection> inside <agent:user> for instruct", function()
    local selection = {
      file = "LICENSE",
      start_line = 5,
      start_col = 31,
      end_line = 5,
      end_col = 44,
      mode = "edit",
      text = "free of charge"
    }

    local _, _, _, _, turn_block = prompts.build_messages("charge $500", "instruct", false, "LICENSE", selection)
    
    -- Verify exact nesting: Selection should come FIRST, followed by Instruction
    assert.match("Target File: LICENSE.-<agent:selection.-free of charge.-</agent:selection>.-Instruction: charge %$500", turn_block)
  end)
end)
