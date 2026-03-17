local M = {}

local api = require("gh-review.api")
local diff = require("gh-review.diff")
local ns = vim.api.nvim_create_namespace("gh_pr_comments")
local pending_ns = vim.api.nvim_create_namespace("gh_pr_pending")

M.visible = false

function M.render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if not M.visible then return end

  diff.render(bufnr)

  local rel_path = api.buf_relative_path(bufnr)
  if not rel_path then return end

  local threads = api.state.threads_by_file[rel_path]
  if not threads then return end

  for _, thread in ipairs(threads) do
    local end_line = thread.line
    if end_line and end_line > 0 then
      local comments = thread.comments and thread.comments.nodes or {}
      if #comments > 0 then
        local hl = thread.isResolved and "GhPrCommentResolved" or "GhPrCommentVirtText"
        local sign_hl = thread.isResolved and "GhPrCommentSignResolved" or "GhPrCommentSign"
        local line_hl = thread.isResolved and "GhPrCommentLineResolved" or "GhPrCommentLine"

        local virt_lines = {}
        for _, comment in ipairs(comments) do
          local author = comment.author and comment.author.login or "unknown"
          local body = comment.body or ""
          local body_lines = vim.split(body, "\n", { trimempty = true })
          for i, body_line in ipairs(body_lines) do
            local prefix = i == 1
              and string.format("  ┊ @%s: ", author)
              or "  ┊   "
            table.insert(virt_lines, { { prefix .. body_line, hl } })
          end
          if #body_lines == 0 then
            table.insert(virt_lines, { { string.format("  ┊ @%s: (empty)", author), hl } })
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
                table.insert(parts, (api.REACTION_EMOJI[key] or key) .. counts[key])
              end
            end
            if #parts > 0 then
              table.insert(virt_lines, { { "  ┊   " .. table.concat(parts, " "), hl } })
            end
          end
        end

        local status = thread.isResolved and "  ┊ [resolved]" or "  ┊ [unresolved]"
        table.insert(virt_lines, { { status, hl } })

        local line_count = vim.api.nvim_buf_line_count(bufnr)

        local start_line = thread.startLine or end_line
        for l = start_line, end_line - 1 do
          if l > 0 and l <= line_count then
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, l - 1, 0, {
              line_hl_group = line_hl,
            })
          end
        end

        if end_line <= line_count then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, end_line - 1, 0, {
            virt_lines = virt_lines,
            line_hl_group = line_hl,
            sign_text = thread.isResolved and "✓" or "●",
            sign_hl_group = sign_hl,
          })
        end
      end
    end
  end
end

function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

function M.clear_all_visible()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    M.clear(bufnr)
  end
end

function M.render_all_visible()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    M.render(bufnr)
  end
end

function M.toggle(bufnr, on_done)
  if M.visible then
    M.visible = false
    M.clear_all_visible()
    diff.clear_all_visible()
    vim.notify("PR comments hidden", vim.log.levels.INFO)
    if on_done then on_done(false) end
  else
    vim.notify("Fetching PR comments & diff...", vim.log.levels.INFO)
    api.fetch_threads(function(threads, err)
      if err then
        vim.notify("GhPr: " .. err, vim.log.levels.ERROR)
        return
      end
      M.visible = true
      diff.fetch_and_render_all_visible(function()
        vim.notify(string.format("Loaded %d comment threads", #(threads or {})), vim.log.levels.INFO)
        M.render_all_visible()
        if on_done then on_done(true) end
      end)
    end)
  end
end

function M.is_visible()
  return M.visible
end

function M.render_pending(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, pending_ns, 0, -1)

  local rel_path = api.buf_relative_path(bufnr)
  if not rel_path then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for _, comment in ipairs(api.state.pending_comments) do
    if comment.path == rel_path and comment.line and comment.line > 0 and comment.line <= line_count then
      local body_lines = vim.split(comment.body, "\n", { trimempty = true })
      local virt_lines = {}
      for i, body_line in ipairs(body_lines) do
        local prefix = i == 1 and "  ┊ [pending] " or "  ┊   "
        table.insert(virt_lines, { { prefix .. body_line, "GhPrCommentPending" } })
      end

      local start_line = comment.start_line or comment.line
      for l = start_line, comment.line - 1 do
        if l > 0 and l <= line_count then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, pending_ns, l - 1, 0, {
            line_hl_group = "GhPrCommentLinePending",
          })
        end
      end

      pcall(vim.api.nvim_buf_set_extmark, bufnr, pending_ns, comment.line - 1, 0, {
        virt_lines = virt_lines,
        line_hl_group = "GhPrCommentLinePending",
        sign_text = "◌",
        sign_hl_group = "GhPrCommentSignPending",
      })
    end
  end
end

function M.clear_pending(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, pending_ns, 0, -1)
end

function M.clear_pending_all_visible()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M.clear_pending(vim.api.nvim_win_get_buf(win))
  end
end

function M.render_pending_all_visible()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M.render_pending(vim.api.nvim_win_get_buf(win))
  end
end

function M.get_thread_at_line(bufnr, line)
  local rel_path = api.buf_relative_path(bufnr)
  if not rel_path then return nil end
  local threads = api.state.threads_by_file[rel_path]
  if not threads then return nil end
  for _, thread in ipairs(threads) do
    if thread.line == line then
      return thread
    end
  end
  return nil
end

function M.get_comment_lines(bufnr)
  local rel_path = api.buf_relative_path(bufnr)
  if not rel_path then return {} end
  local threads = api.state.threads_by_file[rel_path]
  if not threads then return {} end
  local seen = {}
  local lines = {}
  for _, thread in ipairs(threads) do
    if thread.line and thread.line > 0 then
      local start_line = thread.startLine or thread.line
      for l = start_line, thread.line do
        if not seen[l] then
          seen[l] = true
          table.insert(lines, l)
        end
      end
    end
  end
  table.sort(lines)
  return lines
end

function M.get_threads_at_line(bufnr, line)
  local rel_path = api.buf_relative_path(bufnr)
  if not rel_path then return {} end
  local threads = api.state.threads_by_file[rel_path]
  if not threads then return {} end
  local matched = {}
  for _, thread in ipairs(threads) do
    if thread.line == line then
      table.insert(matched, thread)
    end
  end
  return matched
end

return M
