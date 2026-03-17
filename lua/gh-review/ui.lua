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

    local reactions = comment.reactions and comment.reactions.nodes or {}
    if #reactions > 0 then
      local counts = {}
      for _, r in ipairs(reactions) do
        counts[r.content] = (counts[r.content] or 0) + 1
      end
      local parts = {}
      for _, key in ipairs(api.REACTION_ORDER) do
        if counts[key] then
          table.insert(parts, (api.REACTION_EMOJI[key] or key) .. " " .. counts[key])
        end
      end
      if #parts > 0 then
        table.insert(lines, "  " .. table.concat(parts, "  "))
      end
    end

    if i < #comments then
      table.insert(lines, "")
    end
  end

  table.insert(lines, "")
  table.insert(lines, "--- r: reply | R: resolve/unresolve | e: react | q: close ---")

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

  vim.keymap.set("n", "e", function()
    local target_comment
    if #comments == 1 then
      target_comment = comments[1]
    else
      local items = {}
      for _, c in ipairs(comments) do
        local author = c.author and c.author.login or "?"
        local preview = (c.body or ""):match("^([^\n]+)") or "(empty)"
        if #preview > 50 then preview = preview:sub(1, 47) .. "..." end
        table.insert(items, { comment = c, label = string.format("@%s: %s", author, preview) })
      end
      vim.ui.select(items, {
        prompt = "React to which comment? ",
        format_item = function(item) return item.label end,
      }, function(item)
        if not item then return end
        M.pick_reaction(item.comment)
      end)
      return
    end
    M.pick_reaction(target_comment)
  end, { buffer = buf, nowait = true })
end

function M.pick_reaction(comment)
  local viewer = api.state.viewer_login
  local reactions = comment.reactions and comment.reactions.nodes or {}

  local items = {}
  for _, key in ipairs(api.REACTION_ORDER) do
    local emoji = api.REACTION_EMOJI[key] or key
    local count = 0
    local user_reacted = false
    for _, r in ipairs(reactions) do
      if r.content == key then
        count = count + 1
        if viewer and r.user and r.user.login == viewer then
          user_reacted = true
        end
      end
    end
    local suffix = count > 0 and string.format(" (%d)", count) or ""
    local toggle = user_reacted and " [yours]" or ""
    table.insert(items, {
      content = key,
      has_reacted = user_reacted,
      label = string.format("%s %s%s%s", emoji, key:lower():gsub("_", " "), suffix, toggle),
    })
  end

  vim.ui.select(items, {
    prompt = "Toggle reaction: ",
    format_item = function(item) return item.label end,
  }, function(item)
    if not item then return end
    local action = item.has_reacted and "Removing" or "Adding"
    vim.notify(string.format("%s %s...", action, api.REACTION_EMOJI[item.content] or item.content), vim.log.levels.INFO)
    api.toggle_reaction(comment.id, item.content, item.has_reacted, function(ok)
      if ok then
        vim.notify("Reaction updated!", vim.log.levels.INFO)
        refresh_after_action()
      else
        vim.notify("Failed to update reaction", vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.react_to_thread(thread)
  if not thread then
    vim.notify("No comment thread on this line", vim.log.levels.WARN)
    return
  end
  local comments = thread.comments and thread.comments.nodes or {}
  if #comments == 0 then
    vim.notify("No comments to react to", vim.log.levels.WARN)
    return
  end
  if #comments == 1 then
    M.pick_reaction(comments[1])
    return
  end
  local items = {}
  for _, c in ipairs(comments) do
    local author = c.author and c.author.login or "?"
    local preview = (c.body or ""):match("^([^\n]+)") or "(empty)"
    if #preview > 50 then preview = preview:sub(1, 47) .. "..." end
    table.insert(items, { comment = c, label = string.format("@%s: %s", author, preview) })
  end
  vim.ui.select(items, {
    prompt = "React to which comment? ",
    format_item = function(item) return item.label end,
  }, function(item)
    if not item then return end
    M.pick_reaction(item.comment)
  end)
end

function M.reply_to_thread(thread)
  local comments = thread.comments and thread.comments.nodes or {}
  if #comments == 0 then
    vim.notify("No comments to reply to", vim.log.levels.WARN)
    return
  end

  local first_comment_db_id = comments[1].databaseId

  local buf, win = create_float({
    title = string.format(" Reply to @%s on %s:%d | <C-s> send | q cancel ",
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
  vim.keymap.set("n", "<CR>", submit, { buffer = buf })
  vim.keymap.set("n", "<C-s>", submit, { buffer = buf })
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    submit()
  end, { buffer = buf })

  vim.cmd("startinsert")
end

function M.add_comment(line1, line2)
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line = line1 or vim.api.nvim_win_get_cursor(0)[1]
  local end_line = line2 or start_line
  local rel_path = api.buf_relative_path(bufnr)

  if not rel_path then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end
  if not api.state.head_sha then
    vim.notify("PR data not loaded. Run :GhPrToggle or :GhPrRefresh first.", vim.log.levels.ERROR)
    return
  end

  local range_str = start_line == end_line
    and string.format("%s:%d", rel_path, end_line)
    or string.format("%s:%d-%d", rel_path, start_line, end_line)

  local buf, win = create_float({
    title = string.format(" New comment on %s | <C-s> save | q cancel ", range_str),
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
    api.add_pending_comment(rel_path, end_line, start_line ~= end_line and start_line or nil, body)
    local count = api.pending_count()
    vim.notify(string.format("Comment added to pending review (%d pending)", count), vim.log.levels.INFO)
    display.render_pending(bufnr)
  end

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<CR>", submit, { buffer = buf })
  vim.keymap.set("n", "<C-s>", submit, { buffer = buf })
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    submit()
  end, { buffer = buf })

  vim.cmd("startinsert")
end

function M.submit_review(event_arg)
  if not api.state.pr_id then
    vim.notify("PR data not loaded. Run :GhPrToggle or :GhPrRefresh first.", vim.log.levels.ERROR)
    return
  end

  local count = api.pending_count()

  local event_map = {
    approve = "APPROVE",
    comment = "COMMENT",
    request_changes = "REQUEST_CHANGES",
  }

  local function do_submit(event, label)
    local buf, win = create_float({
      title = string.format(" %s — %d comment(s) | <C-s> submit | q cancel ", label, count),
      height = 8,
    })

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

    local function submit()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local body = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      vim.api.nvim_win_close(win, true)

      if event == "REQUEST_CHANGES" and body == "" and count == 0 then
        vim.notify("Request Changes requires a summary or pending comments", vim.log.levels.ERROR)
        return
      end

      vim.notify("Submitting review...", vim.log.levels.INFO)
      api.submit_review(event, body, function(ok, err)
        if ok then
          vim.notify(string.format("Review submitted: %s", label), vim.log.levels.INFO)
          display.clear_pending_all_visible()
          refresh_after_action()
        else
          vim.notify("Failed to submit review: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end
      end)
    end

    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<CR>", submit, { buffer = buf })
    vim.keymap.set("n", "<C-s>", submit, { buffer = buf })
    vim.keymap.set("i", "<C-s>", function()
      vim.cmd("stopinsert")
      submit()
    end, { buffer = buf })

    vim.cmd("startinsert")
  end

  if event_arg then
    local event = event_map[event_arg]
    if not event then
      vim.notify("Invalid event: " .. event_arg .. " (use approve/comment/request_changes)", vim.log.levels.ERROR)
      return
    end
    do_submit(event, event_arg)
  else
    vim.ui.select(
      { "Approve", "Comment", "Request Changes" },
      { prompt = string.format("Submit review (%d pending): ", count) },
      function(choice)
        if not choice then return end
        local map = {
          ["Approve"] = "APPROVE",
          ["Comment"] = "COMMENT",
          ["Request Changes"] = "REQUEST_CHANGES",
        }
        do_submit(map[choice], choice)
      end
    )
  end
end

function M.merge_pr()
  local pr = api.get_pr_number()
  if not pr then
    vim.notify("Not on a PR branch", vim.log.levels.ERROR)
    return
  end

  vim.ui.select(
    { "Merge commit", "Squash and merge", "Rebase and merge" },
    { prompt = string.format("Merge PR #%d: ", pr) },
    function(choice)
      if not choice then return end
      local method_map = {
        ["Merge commit"] = "merge",
        ["Squash and merge"] = "squash",
        ["Rebase and merge"] = "rebase",
      }
      local method = method_map[choice]
      vim.notify(string.format("Merging PR #%d (%s)...", pr, method), vim.log.levels.INFO)
      api.merge_pr(method, function(ok)
        if ok then
          vim.notify(string.format("PR #%d merged!", pr), vim.log.levels.INFO)
        else
          vim.notify("Merge failed (check branch protection / required checks)", vim.log.levels.ERROR)
        end
      end)
    end
  )
end

return M
