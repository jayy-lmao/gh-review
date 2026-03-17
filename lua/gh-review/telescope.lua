local M = {}

function M.list_comments(opts)
  opts = opts or {}
  local api = require("gh-review.api")
  local config = require("gh-review.config")
  local cfg = config.get()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local threads = api.state.threads
  if not threads or #threads == 0 then
    vim.notify("Loading PR data...", vim.log.levels.INFO)
    api.fetch_threads(function(result, err)
      if not result then
        vim.notify(err or "Failed to load PR data", vim.log.levels.ERROR)
        return
      end
      M.list_comments(opts)
    end)
    return
  end

  local filter = opts.filter
  local filtered = {}
  for _, thread in ipairs(threads) do
    if not filter
      or (filter == "resolved" and thread.isResolved)
      or (filter == "unresolved" and not thread.isResolved) then
      table.insert(filtered, thread)
    end
  end

  if #filtered == 0 then
    vim.notify("No " .. (filter or "") .. " comments found", vim.log.levels.INFO)
    return
  end

  local root = api.get_repo_root() or ""

  pickers.new(opts, {
    prompt_title = "PR Comments" .. (filter and (" [" .. filter .. "]") or ""),
    layout_strategy = cfg.layout.strategy,
    layout_config = cfg.layout.config,
    finder = finders.new_table({
      results = filtered,
      entry_maker = function(thread)
        local comments = thread.comments and thread.comments.nodes or {}
        local first = comments[1] or {}
        local author = first.author and first.author.login or "?"
        local body_preview = (first.body or ""):match("^([^\n]+)") or ""
        if #body_preview > 60 then
          body_preview = body_preview:sub(1, 57) .. "..."
        end
        local status = thread.isResolved and "+" or "x"
        local replies = #comments > 1 and string.format(" [+%d]", #comments - 1) or ""
        local line = (type(thread.line) == "number") and thread.line or 0
        local display_str = string.format("[%s] %s:%d @%s: %s%s",
          status, thread.path or "?", line, author, body_preview, replies)

        return {
          value = thread,
          display = display_str,
          ordinal = display_str,
          filename = thread.path,
          lnum = line > 0 and line or 1,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = "Diff with Comments",
      define_preview = function(self, entry)
        local thread = entry.value
        if not thread or not thread.path then return end
        local bufnr = self.state.bufnr
        local base = api.get_base_branch()
        if not base then
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Cannot determine base branch" })
          return
        end

        vim.fn.jobstart({
          "git", "-C", root, "diff", base .. "..HEAD", "--", thread.path,
        }, {
          stdout_buffered = true,
          on_stdout = function(_, data)
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(bufnr) then return end
              if data and data[#data] == "" then table.remove(data) end
              if not data or #data == 0 then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No diff available" })
                return
              end

              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, data)
              vim.api.nvim_set_option_value("filetype", "diff", { buf = bufnr })

              local target_line = thread.line
              if not target_line then return end
              local display_line = nil
              local new_line_num = 0
              for i, line in ipairs(data) do
                local ns_val = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")
                if ns_val then
                  new_line_num = tonumber(ns_val) - 1
                elseif new_line_num > 0 then
                  local prefix = line:sub(1, 1)
                  if prefix == "+" or prefix == " " then
                    new_line_num = new_line_num + 1
                    if new_line_num == target_line then
                      display_line = i
                      break
                    end
                  end
                end
              end

              if not display_line then return end

              local preview_ns = vim.api.nvim_create_namespace("gh_pr_preview")
              local comments = thread.comments and thread.comments.nodes or {}
              local hl = thread.isResolved and "GhPrCommentResolved" or "GhPrCommentVirtText"
              local virt_lines = {}
              for _, comment in ipairs(comments) do
                local c_author = comment.author and comment.author.login or "unknown"
                local body = comment.body or ""
                local body_lines = vim.split(body, "\n", { trimempty = true })
                for j, body_line in ipairs(body_lines) do
                  local virt_prefix = j == 1
                    and string.format("  ┊ @%s: ", c_author)
                    or "  ┊   "
                  table.insert(virt_lines, { { virt_prefix .. body_line, hl } })
                end
                if #body_lines == 0 then
                  table.insert(virt_lines, { { string.format("  ┊ @%s: (empty)", c_author), hl } })
                end
              end
              local comment_status = thread.isResolved and "  ┊ [resolved]" or "  ┊ [unresolved]"
              table.insert(virt_lines, { { comment_status, hl } })

              pcall(vim.api.nvim_buf_set_extmark, bufnr, preview_ns, display_line - 1, 0, {
                virt_lines = virt_lines,
              })

              pcall(function()
                vim.api.nvim_win_set_cursor(self.state.winid, { display_line, 0 })
                vim.api.nvim_win_call(self.state.winid, function()
                  vim.cmd("normal! zt")
                end)
              end)
            end)
          end,
        })
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.value then
          local thread = entry.value
          local r = api.get_repo_root()
          if r and thread.path then
            local filepath = r .. "/" .. thread.path
            if vim.fn.filereadable(filepath) == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(filepath))
              if thread.line then
                vim.api.nvim_win_set_cursor(0, { thread.line, 0 })
              end
              require("gh-review.ui").show_thread(thread)
            else
              vim.notify("File not found: " .. filepath, vim.log.levels.WARN)
            end
          end
        end
      end)
      return true
    end,
  }):find()
end

function M.list_files(opts)
  opts = opts or {}
  local api = require("gh-review.api")
  local config = require("gh-review.config")
  local cfg = config.get()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local files = api.state.changed_files
  if not files or #files == 0 then
    vim.notify("Loading PR data...", vim.log.levels.INFO)
    api.fetch_threads(function(result, err)
      if not result then
        vim.notify(err or "Failed to load PR data", vim.log.levels.ERROR)
        return
      end
      M.list_files(opts)
    end)
    return
  end

  local VIEWED_CHECK = "[✓]"
  local UNVIEWED_CHECK = "[ ]"

  local function format_display(file)
    local check = file.viewerViewedState == "VIEWED" and VIEWED_CHECK or UNVIEWED_CHECK
    return string.format("%s %s (+%d -%d) %s",
      check, file.path, file.additions or 0, file.deletions or 0, file.changeType or "")
  end

  local sorted = {}
  for _, f in ipairs(files) do table.insert(sorted, f) end
  table.sort(sorted, function(a, b) return a.path < b.path end)

  local root = api.get_repo_root() or ""

  pickers.new(opts, {
    prompt_title = "PR Changed Files",
    layout_strategy = cfg.layout.strategy,
    layout_config = cfg.layout.config,
    finder = finders.new_table({
      results = sorted,
      entry_maker = function(file)
        return {
          value = file,
          display = format_display(file),
          ordinal = file.path,
          filename = root .. "/" .. file.path,
          path = root .. "/" .. file.path,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_termopen_previewer({
      title = "Diff Preview",
      get_command = function(entry)
        if not entry or not entry.value then return end
        local base = api.get_base_branch()
        if not base then return { "echo", "Cannot determine base branch" } end
        return { "git", "-C", root, "diff", "--color=always", base .. "..HEAD", "--", entry.value.path }
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.value then
          local r = api.get_repo_root()
          if r and entry.value.path then
            local filepath = r .. "/" .. entry.value.path
            if vim.fn.filereadable(filepath) == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(filepath))
            else
              vim.notify("File not found: " .. filepath, vim.log.levels.WARN)
            end
          end
        end
      end)

      local function toggle_viewed()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry or not entry.value or not picker then return end
        local file = entry.value
        local is_viewed = file.viewerViewedState == "VIEWED"
        local toggle_fn = is_viewed and api.mark_file_unviewed or api.mark_file_viewed
        local row = picker:get_selection_row()
        local results_bufnr = picker.results_bufnr
        local old_check = is_viewed and VIEWED_CHECK or UNVIEWED_CHECK
        local new_check = is_viewed and UNVIEWED_CHECK or VIEWED_CHECK
        toggle_fn(file.path, function(ok)
          if not ok then
            vim.notify("Failed to toggle viewed status", vim.log.levels.ERROR)
            return
          end
          if results_bufnr and vim.api.nvim_buf_is_valid(results_bufnr) then
            local line = vim.api.nvim_buf_get_lines(results_bufnr, row, row + 1, false)[1]
            if line then
              local col_start, col_end = line:find(old_check, 1, true)
              if col_start then
                vim.api.nvim_buf_set_text(results_bufnr, row, col_start - 1, row, col_end, { new_check })
              end
            end
          end
        end)
      end

      map("i", "<C-v>", toggle_viewed)
      map("n", "<C-v>", toggle_viewed)

      return true
    end,
  }):find()
end

function M.list_prs(opts)
  opts = opts or {}
  local api = require("gh-review.api")
  local config = require("gh-review.config")
  local cfg = config.get()
  local icons = cfg.icons
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  local entry_display = require("telescope.pickers.entry_display")

  if not api.state.repo_prs then
    vim.notify("Loading PRs...", vim.log.levels.INFO)
    api.fetch_repo_prs(function(result, err)
      if not result then
        vim.notify(err or "Failed to load PRs", vim.log.levels.ERROR)
        return
      end
      M.list_prs(opts)
    end)
    return
  end

  local viewer = api.state.viewer_login
  local filter = opts.filter

  local filtered = {}
  for _, pr in ipairs(api.state.repo_prs) do
    local author = pr.author and pr.author.login or ""
    if not filter
      or (filter == "mine" and author == viewer)
      or (filter == "others" and author ~= viewer) then
      table.insert(filtered, pr)
    end
  end

  if #filtered == 0 then
    vim.notify("No PRs found" .. (filter and (" for filter: " .. filter) or ""), vim.log.levels.INFO)
    return
  end

  local function format_ci(pr)
    local checks = pr.statusCheckRollup or {}
    if type(checks) ~= "table" or #checks == 0 then return icons.ci_none, "GhPrCiNone" end
    local has_fail = false
    local has_pending = false
    for _, c in ipairs(checks) do
      local conclusion = c.conclusion or ""
      local status = c.status or ""
      if conclusion == "FAILURE" or conclusion == "ERROR" then
        has_fail = true
        break
      elseif status ~= "COMPLETED" or conclusion == "" then
        has_pending = true
      end
    end
    if has_fail then return icons.ci_fail, "GhPrCiFail" end
    if has_pending then return icons.ci_pending, "GhPrCiPending" end
    return icons.ci_pass, "GhPrCiPass"
  end

  local function format_review(pr)
    local decision = pr.reviewDecision
    if not decision or decision == "" then return icons.review_wait, "GhPrReviewWait" end
    if decision == "APPROVED" then return icons.approved, "GhPrApproved" end
    if decision == "CHANGES_REQUESTED" then return icons.changes_requested, "GhPrChangesRequested" end
    return icons.review_wait, "GhPrReviewWait"
  end

  local function format_state(pr)
    if pr.isDraft then return icons.draft, "GhPrDraft" end
    return icons.open, "GhPrOpen"
  end

  local function time_ago(iso_str)
    if not iso_str or iso_str == "" then return "" end
    local y, m, d, h, mi, s = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return iso_str:sub(1, 10) end
    local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d),
      hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
    local diff = os.time() - ts
    if diff < 60 then return "now"
    elseif diff < 3600 then return math.floor(diff / 60) .. "m"
    elseif diff < 86400 then return math.floor(diff / 3600) .. "h"
    elseif diff < 604800 then return math.floor(diff / 86400) .. "d"
    elseif diff < 2592000 then return math.floor(diff / 604800) .. "w"
    else return math.floor(diff / 2592000) .. "mo" end
  end

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 2 },  -- state icon
      { width = 2 },  -- CI icon
      { width = 2 },  -- review icon
      { width = 6 },  -- #number
      { width = 14 }, -- author
      { remaining = true }, -- title
      { width = 4 },  -- created
      { width = 4 },  -- updated
    },
  })

  local filter_cycle = { mine = "others", others = nil, [false] = "mine" }

  pickers.new(opts, {
    prompt_title = "Open PRs" .. (filter and (" [" .. filter .. "]") or ""),
    layout_strategy = cfg.layout.strategy,
    layout_config = cfg.layout.config,
    finder = finders.new_table({
      results = filtered,
      entry_maker = function(pr)
        local state_icon, state_hl = format_state(pr)
        local ci_icon, ci_hl = format_ci(pr)
        local review_icon, review_hl = format_review(pr)
        local author = pr.author and pr.author.login or "?"
        local title = pr.title or ""
        local author_part = ""
        if filter ~= "mine" and author ~= viewer then
          author_part = "@" .. author
        end
        local created = time_ago(pr.createdAt)
        local updated = time_ago(pr.updatedAt)

        return {
          value = pr,
          ordinal = string.format("%d %s %s", pr.number, author, title),
          display = function(entry)
            return displayer({
              { state_icon, state_hl },
              { ci_icon, ci_hl },
              { review_icon, review_hl },
              { "#" .. pr.number, "GhPrNumber" },
              { author_part, "GhPrAuthor" },
              title,
              { created, "GhPrTime" },
              { updated, "GhPrTime" },
            })
          end,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_termopen_previewer({
      title = "PR Details",
      get_command = function(entry)
        if not entry or not entry.value then return { "echo", "" } end
        return { "gh", "pr", "view", tostring(entry.value.number) }
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry or not entry.value then return end
        local pr = entry.value
        vim.notify(string.format("Checking out PR #%d...", pr.number), vim.log.levels.INFO)
        vim.fn.jobstart({ "gh", "pr", "checkout", tostring(pr.number) }, {
          on_exit = function(_, exit_code)
            vim.schedule(function()
              if exit_code ~= 0 then
                vim.notify("Failed to checkout PR #" .. pr.number, vim.log.levels.ERROR)
                return
              end
              local pending = api.pending_count()
              if pending > 0 then
                vim.notify(string.format("Discarded %d pending comment(s) from previous PR", pending), vim.log.levels.WARN)
              end
              api.invalidate()
              api.discard_pending()
              api.state.pr_number = pr.number
              vim.notify(string.format("Switched to PR #%d: %s", pr.number, pr.title or ""), vim.log.levels.INFO)
            end)
          end,
        })
      end)

      local function open_in_browser()
        local entry = action_state.get_selected_entry()
        if not entry or not entry.value then return end
        vim.fn.jobstart({ "gh", "pr", "view", "--web", tostring(entry.value.number) })
      end

      local function toggle_filter()
        actions.close(prompt_bufnr)
        local next_filter = filter_cycle[filter or false]
        M.list_prs({ filter = next_filter })
      end

      map("i", "<C-o>", open_in_browser)
      map("n", "<C-o>", open_in_browser)
      map("i", "<C-t>", toggle_filter)
      map("n", "<C-t>", toggle_filter)

      return true
    end,
  }):find()
end

return M
