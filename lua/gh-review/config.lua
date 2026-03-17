local M = {}

M.defaults = {
  -- Telescope layout for all pickers
  layout = {
    strategy = "vertical",
    config = {
      width = 0.9,
      height = 0.9,
      preview_height = 0.5,
    },
  },

  -- Nerd Font icons (set to plain text alternatives if no nerd font)
  icons = {
    open = "",           -- nf-oct-git_pull_request
    draft = "",          -- nf-oct-git_pull_request_draft
    ci_pass = "",        -- nf-md-check_all
    ci_fail = "󰅙",        -- nf-md-close_circle
    ci_pending = "",     -- nf-oct-dot_fill
    ci_none = " ",
    approved = "󰄬",       -- nf-md-check
    changes_requested = "", -- nf-cod-request_changes
    review_wait = "",    -- nf-oct-dot_fill
  },

  -- Highlight groups (all use `default = true` so user overrides win)
  highlights = {
    open = { fg = "#3fb950" },
    draft = { fg = "#768390" },
    ci_pass = { fg = "#3fb950" },
    ci_fail = { fg = "#f85149" },
    ci_pending = { fg = "#d29922" },
    ci_none = { fg = "#768390" },
    approved = { fg = "#3fb950" },
    changes_requested = { fg = "#f85149" },
    review_wait = { fg = "#d29922" },
    number = { fg = "#768390" },
    author = { fg = "#768390" },
    time = { fg = "#768390" },

    -- Inline comment overlays
    comment = { link = "DiagnosticVirtualTextWarn" },
    comment_resolved = { link = "DiagnosticVirtualTextHint" },
    comment_sign = { link = "DiagnosticSignInfo" },
    comment_sign_resolved = { link = "DiagnosticSignHint" },
    comment_line = { bg = "#2a2a1a" },
    comment_line_resolved = { bg = "#1a2a2a" },

    -- Diff overlays
    diff_add = { bg = "#1a3a1a" },
    diff_add_sign = { fg = "#4ae04a" },
    diff_delete = { fg = "#a06060", bg = "#2a1515" },
    diff_delete_sign = { fg = "#a06060" },
  },

  -- PR list settings
  pr_list = {
    limit = 50,
  },
}

M.values = {}

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

function M.get()
  return M.values
end

return M
