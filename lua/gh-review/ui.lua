local M = {}

local api = require("gh-review.api")
local display = require("gh-review.display")

local function create_float(opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.6)
  local height = opts.height or math.floor(vim.o.lines * 0.4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = opts.title or "",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("wrap", true, { win = win })
  return buf, win
end

local function refresh_after_action()
  api.fetch_threads(function()
    display.render_all_visible()
  end)
end

function M.show_thread(thread)
  if not thread then
    vim.notify("No comment thread on this line", vim.log.levels.WARN)
    return
  end

  local comments = thread.comments and thread.comments.nodes or {}
  local lines = {}
  local status = thread.isResolved and "RESOLVED" or "UNRESOLVED"
  table.insert(lines, string.format("--- %s --- %s:%d ---", status, thread.path, thread.line or 0))
  if thread.isOutdated then
    table.insert(lines, "!! Outdated - code has changed since this comment")
  end
  table.insert(lines, "")

  for i, comment in ipairs(comments) do
    local author = comment.author and comment.author.login or "unknown"
    local date = (comment.createdAt or ""):sub(1, 10)
    table.insert(lines, string.format("@%s (%s):", author, date))
    for body_line in comment.body:gmatch("([^\n]*)") do
      table.insert(lines, "  " .. body_line)
    end
    if i < #comments then
      table.insert(lines, "")
    end
  end

  table.insert(lines, "")
  table.insert(lines, "--- r: reply | R: resolve/unresolve | q: close ---")

  local buf, win = create_float({ title = " PR Thread " })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "r", function()
    vim.api.nvim_win_close(win, true)
    M.reply_to_thread(thread)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "R", function()
    vim.api.nvim_win_close(win, true)
    if thread.isResolved then
      vim.notify("Unresolving thread...", vim.log.levels.INFO)
      api.unresolve_thread(thread.id, function(ok)
        if ok then
          vim.notify("Thread unresolved", vim.log.levels.INFO)
          refresh_after_action()
        else
          vim.notify("Failed to unresolve thread", vim.log.levels.ERROR)
        end
      end)
    else
      vim.notify("Resolving thread...", vim.log.levels.INFO)
      api.resolve_thread(thread.id, function(ok)
        if ok then
          vim.notify("Thread resolved", vim.log.levels.INFO)
          refresh_after_action()
        else
          vim.notify("Failed to resolve thread", vim.log.levels.ERROR)
        end
      end)
    end
  end, { buffer = buf, nowait = true })
end

function M.reply_to_thread(thread)
  local comments = thread.comments and thread.comments.nodes or {}
  if #comments == 0 then
    vim.notify("No comments to reply to", vim.log.levels.WARN)
    return
  end

  local first_comment_db_id = comments[1].databaseId

  local buf, win = create_float({
    title = string.format(" Reply to @%s on %s:%d ",
      comments[1].author and comments[1].author.login or "?",
      thread.path, thread.line or 0),
    height = 10,
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  local function submit()
    local reply_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = table.concat(reply_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if body == "" then
      vim.notify("Empty reply, cancelled", vim.log.levels.WARN)
      return
    end
    vim.api.nvim_win_close(win, true)
    vim.notify("Posting reply...", vim.log.levels.INFO)
    api.reply_to_comment(first_comment_db_id, body, function(ok)
      if ok then
        vim.notify("Reply posted!", vim.log.levels.INFO)
        refresh_after_action()
      else
        vim.notify("Failed to post reply", vim.log.levels.ERROR)
      end
    end)
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<C-s>", submit, { buffer = buf })
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    submit()
  end, { buffer = buf })

  vim.cmd("startinsert")
end

function M.add_comment()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local rel_path = api.buf_relative_path(bufnr)

  if not rel_path then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end
  if not api.state.head_sha then
    vim.notify("PR data not loaded. Run :GhPrRefresh first.", vim.log.levels.ERROR)
    return
  end

  local buf, win = create_float({
    title = string.format(" New comment on %s:%d ", rel_path, cursor_line),
    height = 10,
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  local function submit()
    local comment_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = table.concat(comment_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if body == "" then
      vim.notify("Empty comment, cancelled", vim.log.levels.WARN)
      return
    end
    vim.api.nvim_win_close(win, true)
    vim.notify("Posting comment...", vim.log.levels.INFO)
    api.add_comment(rel_path, cursor_line, body, function(ok)
      if ok then
        vim.notify("Comment posted!", vim.log.levels.INFO)
        refresh_after_action()
      else
        vim.notify("Failed to post comment", vim.log.levels.ERROR)
      end
    end)
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<C-s>", submit, { buffer = buf })
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    submit()
  end, { buffer = buf })

  vim.cmd("startinsert")
end

return M
