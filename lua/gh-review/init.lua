local M = {}

function M.setup()
  local api = require("gh-review.api")
  local display = require("gh-review.display")
  local diff = require("gh-review.diff")
  local ui = require("gh-review.ui")
  local telescope = require("gh-review.telescope")

  vim.api.nvim_create_user_command("GhPrToggle", function()
    display.toggle()
  end, {})

  vim.api.nvim_create_user_command("GhPrRefresh", function()
    if not display.is_visible() then
      vim.notify("PR comments are off. Use :GhPrToggle to enable.", vim.log.levels.WARN)
      return
    end
    vim.notify("Refreshing PR comments & diff...", vim.log.levels.INFO)
    api.invalidate()
    diff.invalidate()
    api.fetch_threads(function(threads, err)
      if err then
        vim.notify("GhPr: " .. err, vim.log.levels.ERROR)
        return
      end
      diff.fetch_and_render_all_visible(function()
        vim.notify(string.format("Loaded %d comment threads", #(threads or {})), vim.log.levels.INFO)
        display.render_all_visible()
      end)
    end)
  end, {})

  vim.api.nvim_create_user_command("GhPrComments", function(cmd_opts)
    local filter = nil
    if cmd_opts.args == "resolved" then filter = "resolved"
    elseif cmd_opts.args == "unresolved" then filter = "unresolved"
    end
    telescope.list_comments({ filter = filter })
  end, {
    nargs = "?",
    complete = function() return { "resolved", "unresolved" } end,
  })

  vim.api.nvim_create_user_command("GhPrFiles", function()
    telescope.list_files()
  end, {})

  vim.api.nvim_create_user_command("GhPrList", function(cmd_opts)
    local filter = nil
    if cmd_opts.args == "mine" then filter = "mine"
    elseif cmd_opts.args == "others" then filter = "others"
    end
    telescope.list_prs({ filter = filter })
  end, {
    nargs = "?",
    complete = function() return { "mine", "others" } end,
  })

  vim.api.nvim_create_user_command("GhPrAddComment", function()
    ui.add_comment()
  end, {})

  vim.api.nvim_create_user_command("GhPrViewThread", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local thread = display.get_thread_at_line(bufnr, line)
    ui.show_thread(thread)
  end, {})

  vim.api.nvim_create_user_command("GhPrReply", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local thread = display.get_thread_at_line(bufnr, line)
    if not thread then
      vim.notify("No comment thread on this line", vim.log.levels.WARN)
      return
    end
    ui.reply_to_thread(thread)
  end, {})

  vim.api.nvim_create_user_command("GhPrNextComment", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local lines = display.get_comment_lines(bufnr)
    if #lines == 0 then
      vim.notify("No PR comments in this file", vim.log.levels.INFO)
      return
    end
    local target = nil
    for _, l in ipairs(lines) do
      if l > cursor then target = l break end
    end
    target = target or lines[1]
    vim.api.nvim_win_set_cursor(0, { target, 0 })
  end, {})

  vim.api.nvim_create_user_command("GhPrPrevComment", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local lines = display.get_comment_lines(bufnr)
    if #lines == 0 then
      vim.notify("No PR comments in this file", vim.log.levels.INFO)
      return
    end
    local target = nil
    for i = #lines, 1, -1 do
      if lines[i] < cursor then target = lines[i] break end
    end
    target = target or lines[#lines]
    vim.api.nvim_win_set_cursor(0, { target, 0 })
  end, {})

  vim.api.nvim_create_user_command("GhPrClear", function()
    display.visible = false
    display.clear_all_visible()
    diff.clear_all_visible()
    diff.invalidate()
    api.invalidate()
    vim.notify("PR comments cleared", vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("GhReview", { clear = true }),
    callback = function(ev)
      if display.is_visible() then
        diff.fetch_and_render(ev.buf, function()
          display.render(ev.buf)
        end)
      end
    end,
  })
end

return M
