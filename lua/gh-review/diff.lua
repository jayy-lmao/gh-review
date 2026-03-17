local M = {}

local api = require("gh-review.api")
local ns = vim.api.nvim_create_namespace("gh_pr_diff")

M.state = {
  hunks_by_file = {},
}

local function setup_highlights()
  vim.api.nvim_set_hl(0, "GhPrDiffAdd", { bg = "#1a3a1a", default = true })
  vim.api.nvim_set_hl(0, "GhPrDiffAddSign", { fg = "#4ae04a", default = true })
  vim.api.nvim_set_hl(0, "GhPrDiffDelete", { fg = "#a06060", bg = "#2a1515", default = true })
  vim.api.nvim_set_hl(0, "GhPrDiffDeleteSign", { fg = "#a06060", default = true })
end

function M.parse_unified_diff(diff_lines)
  local hunks = {}
  local current_hunk = nil

  for _, line in ipairs(diff_lines) do
    local ns_val, nc_val = line:match("^@@ %-%d+,?%d* %+(%d+),?(%d*) @@")
    if ns_val then
      current_hunk = {
        new_start = tonumber(ns_val),
        lines = {},
      }
      table.insert(hunks, current_hunk)
    elseif current_hunk then
      if line:sub(1, 1) == "+" then
        table.insert(current_hunk.lines, { type = "add", text = line:sub(2) })
      elseif line:sub(1, 1) == "-" then
        table.insert(current_hunk.lines, { type = "delete", text = line:sub(2) })
      elseif line:sub(1, 1) == " " then
        table.insert(current_hunk.lines, { type = "context", text = line:sub(2) })
      end
    end
  end

  return hunks
end

function M.fetch_diff(rel_path, callback)
  local root = api.get_repo_root()
  if not root then
    if callback then callback(nil, "No git root") end
    return
  end

  local base = api.get_base_branch()
  if not base then
    if callback then callback(nil, "Cannot determine base branch") end
    return
  end

  vim.fn.jobstart({
    "git", "-C", root, "diff", base .. "..HEAD", "--", rel_path,
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.schedule(function()
        if not data or #data == 0 then
          if callback then callback({}) end
          return
        end
        local hunks = M.parse_unified_diff(data)
        M.state.hunks_by_file[rel_path] = hunks
        if callback then callback(hunks) end
      end)
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.schedule(function()
          M.state.hunks_by_file[rel_path] = {}
          if callback then callback({}) end
        end)
      end
    end,
  })
end

function M.render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  setup_highlights()

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local rel_path = api.buf_relative_path(bufnr)
  if not rel_path then return end

  local hunks = M.state.hunks_by_file[rel_path]
  if not hunks then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for _, hunk in ipairs(hunks) do
    local new_line = hunk.new_start
    local pending_deletes = {}

    for _, hline in ipairs(hunk.lines) do
      if hline.type == "delete" then
        table.insert(pending_deletes, hline.text)
      else
        if #pending_deletes > 0 and new_line >= 1 and new_line <= line_count then
          local virt_lines = {}
          for _, del_text in ipairs(pending_deletes) do
            table.insert(virt_lines, { { "- ", "GhPrDiffDeleteSign" }, { del_text, "GhPrDiffDelete" } })
          end
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, new_line - 1, 0, {
            virt_lines = virt_lines,
            virt_lines_above = true,
          })
        end
        pending_deletes = {}

        if hline.type == "add" then
          if new_line >= 1 and new_line <= line_count then
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, new_line - 1, 0, {
              line_hl_group = "GhPrDiffAdd",
              sign_text = "+",
              sign_hl_group = "GhPrDiffAddSign",
            })
          end
        end

        new_line = new_line + 1
      end
    end

    if #pending_deletes > 0 then
      local attach_line = math.min(new_line, line_count)
      if attach_line >= 1 then
        local virt_lines = {}
        for _, del_text in ipairs(pending_deletes) do
          table.insert(virt_lines, { { "- ", "GhPrDiffDeleteSign" }, { del_text, "GhPrDiffDelete" } })
        end
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, attach_line - 1, 0, {
          virt_lines = virt_lines,
          virt_lines_above = (new_line <= line_count),
        })
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

function M.fetch_and_render(bufnr, callback)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local rel_path = api.buf_relative_path(bufnr)
  if not rel_path then
    if callback then callback() end
    return
  end

  M.fetch_diff(rel_path, function()
    M.render(bufnr)
    if callback then callback() end
  end)
end

function M.fetch_and_render_all_visible(callback)
  local wins = vim.api.nvim_list_wins()
  local pending = 0

  for _, win in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    local rel_path = api.buf_relative_path(bufnr)
    if rel_path then
      pending = pending + 1
    end
  end

  if pending == 0 then
    if callback then callback() end
    return
  end

  for _, win in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    local rel_path = api.buf_relative_path(bufnr)
    if rel_path then
      M.fetch_diff(rel_path, function()
        M.render(bufnr)
        pending = pending - 1
        if pending == 0 and callback then callback() end
      end)
    end
  end
end

function M.invalidate()
  M.state.hunks_by_file = {}
end

return M
