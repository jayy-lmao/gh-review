local M = {}

local function check_deps()
  local ok, _ = pcall(require, "telescope")
  if not ok then
    vim.notify("gh-review.nvim requires telescope.nvim", vim.log.levels.ERROR)
    return false
  end
  if vim.fn.executable("gh") ~= 1 then
    vim.notify("gh-review.nvim requires the gh CLI (https://cli.github.com/)", vim.log.levels.ERROR)
    return false
  end
  return true
end

local function check_gh_auth()
  vim.fn.jobstart({ "gh", "auth", "status" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.schedule(function()
          vim.notify("gh-review.nvim: gh CLI is not authenticated. Run `gh auth login`.", vim.log.levels.WARN)
        end)
      end
    end,
  })
end

local function setup_highlights(cfg)
  local hl = cfg.highlights
  vim.api.nvim_set_hl(0, "GhPrOpen", vim.tbl_extend("force", hl.open, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrDraft", vim.tbl_extend("force", hl.draft, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCiPass", vim.tbl_extend("force", hl.ci_pass, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCiFail", vim.tbl_extend("force", hl.ci_fail, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCiPending", vim.tbl_extend("force", hl.ci_pending, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCiNone", vim.tbl_extend("force", hl.ci_none, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrApproved", vim.tbl_extend("force", hl.approved, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrChangesRequested", vim.tbl_extend("force", hl.changes_requested, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrReviewWait", vim.tbl_extend("force", hl.review_wait, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrNumber", vim.tbl_extend("force", hl.number, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrAuthor", vim.tbl_extend("force", hl.author, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrTime", vim.tbl_extend("force", hl.time, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentVirtText", vim.tbl_extend("force", hl.comment, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentResolved", vim.tbl_extend("force", hl.comment_resolved, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentSign", vim.tbl_extend("force", hl.comment_sign, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentSignResolved", vim.tbl_extend("force", hl.comment_sign_resolved, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentLine", vim.tbl_extend("force", hl.comment_line, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentLineResolved", vim.tbl_extend("force", hl.comment_line_resolved, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrDiffAdd", vim.tbl_extend("force", hl.diff_add, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrDiffAddSign", vim.tbl_extend("force", hl.diff_add_sign, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrDiffDelete", vim.tbl_extend("force", hl.diff_delete, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrDiffDeleteSign", vim.tbl_extend("force", hl.diff_delete_sign, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentPending", vim.tbl_extend("force", hl.comment_pending, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentSignPending", vim.tbl_extend("force", hl.comment_sign_pending, { default = true }))
  vim.api.nvim_set_hl(0, "GhPrCommentLinePending", vim.tbl_extend("force", hl.comment_line_pending, { default = true }))
end

function M.setup(opts)
  if not check_deps() then return end

  local config = require("gh-review.config")
  config.setup(opts)
  local cfg = config.get()

  setup_highlights(cfg)
  check_gh_auth()

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

  vim.api.nvim_create_user_command("GhPrAddComment", function(cmd_opts)
    ui.add_comment(cmd_opts.line1, cmd_opts.line2)
  end, { range = true })

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

  vim.api.nvim_create_user_command("GhPrReact", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local thread = display.get_thread_at_line(bufnr, line)
    ui.react_to_thread(thread)
  end, {})

  vim.api.nvim_create_user_command("GhPrSubmitReview", function(cmd_opts)
    local arg = cmd_opts.args ~= "" and cmd_opts.args or nil
    ui.submit_review(arg)
  end, {
    nargs = "?",
    complete = function() return { "approve", "comment", "request_changes" } end,
  })

  vim.api.nvim_create_user_command("GhPrMerge", function()
    ui.merge_pr()
  end, {})

  vim.api.nvim_create_user_command("GhPrPending", function()
    local count = api.pending_count()
    if count == 0 then
      vim.notify("No pending review comments", vim.log.levels.INFO)
    else
      vim.notify(string.format("%d pending review comment(s)", count), vim.log.levels.INFO)
    end
  end, {})

  vim.api.nvim_create_user_command("GhPrDiscardReview", function()
    local count = api.pending_count()
    if count == 0 then
      vim.notify("No pending comments to discard", vim.log.levels.INFO)
      return
    end
    api.discard_pending()
    display.clear_pending_all_visible()
    vim.notify(string.format("Discarded %d pending comment(s)", count), vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("GhPrClear", function()
    display.visible = false
    display.clear_all_visible()
    display.clear_pending_all_visible()
    diff.clear_all_visible()
    diff.invalidate()
    api.invalidate()
    api.discard_pending()
    vim.notify("PR comments cleared", vim.log.levels.INFO)
  end, {})

  if cfg.keymaps then
    local map = vim.keymap.set
    local o = { silent = true }

    -- PR browsing
    map("n", "<leader>gl", "<cmd>GhPrList<cr>", vim.tbl_extend("force", o, { desc = "PR list" }))
    map("n", "<leader>gf", "<cmd>GhPrFiles<cr>", vim.tbl_extend("force", o, { desc = "PR changed files" }))
    map("n", "<leader>gc", "<cmd>GhPrComments<cr>", vim.tbl_extend("force", o, { desc = "PR comments" }))

    -- Toggle / refresh
    map("n", "<leader>gt", "<cmd>GhPrToggle<cr>", vim.tbl_extend("force", o, { desc = "Toggle PR overlays" }))
    map("n", "<leader>gx", "<cmd>GhPrClear<cr>", vim.tbl_extend("force", o, { desc = "Clear PR overlays" }))

    -- Comments & threads
    map("n", "<leader>ga", "<cmd>GhPrAddComment<cr>", vim.tbl_extend("force", o, { desc = "Add review comment" }))
    map("v", "<leader>ga", ":GhPrAddComment<cr>", vim.tbl_extend("force", o, { desc = "Add review comment on selection" }))
    map("n", "<leader>gv", "<cmd>GhPrViewThread<cr>", vim.tbl_extend("force", o, { desc = "View thread" }))
    map("n", "<leader>gr", "<cmd>GhPrReply<cr>", vim.tbl_extend("force", o, { desc = "Reply to thread" }))
    map("n", "]g", "<cmd>GhPrNextComment<cr>", vim.tbl_extend("force", o, { desc = "Next PR comment" }))
    map("n", "[g", "<cmd>GhPrPrevComment<cr>", vim.tbl_extend("force", o, { desc = "Prev PR comment" }))

    -- Reactions
    map("n", "<leader>ge", "<cmd>GhPrReact<cr>", vim.tbl_extend("force", o, { desc = "React to comment" }))

    -- Review workflow
    map("n", "<leader>gs", "<cmd>GhPrSubmitReview<cr>", vim.tbl_extend("force", o, { desc = "Submit review" }))
    map("n", "<leader>gd", "<cmd>GhPrDiscardReview<cr>", vim.tbl_extend("force", o, { desc = "Discard pending review" }))
    map("n", "<leader>gp", "<cmd>GhPrPending<cr>", vim.tbl_extend("force", o, { desc = "Pending comment count" }))

    -- Merge
    map("n", "<leader>gm", "<cmd>GhPrMerge<cr>", vim.tbl_extend("force", o, { desc = "Merge PR" }))
  end

  local augroup = vim.api.nvim_create_augroup("GhReview", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = function()
      setup_highlights(config.get())
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      display.render_pending(ev.buf)
      if display.is_visible() then
        diff.fetch_and_render(ev.buf, function()
          display.render(ev.buf)
        end)
      end
    end,
  })
end

return M
