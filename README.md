# gh-review.nvim

A Neovim plugin for reviewing GitHub pull requests without leaving your editor. Browse PRs, view inline comments with diff context, reply to threads, and manage file review state — all powered by the `gh` CLI.

## Features

- **PR List** — Telescope picker showing open PRs with colored status icons (CI, review, draft state), filterable by author
- **Inline Comments** — Virtual text overlays showing PR review threads directly on your source code
- **Diff Highlighting** — Inline diff rendering (additions/deletions) against the base branch
- **File Review** — Browse changed files with viewed/unviewed status, toggle with a keypress
- **Thread Actions** — View, reply to, resolve/unresolve comment threads from floating windows
- **PR Checkout** — Check out any PR branch directly from the picker
- **Reactions** — View emoji reactions on comments and toggle your own (👍 👎 😄 🎉 😕 ❤️ 🚀 👀)
- **Review Submission** — Batch comments into a pending review, then submit as Approve / Request Changes / Comment
- **Multi-line Comments** — Select a visual range to comment on multiple lines at once
- **Merge PR** — Merge, squash, or rebase directly from Neovim

## Requirements

- Neovim >= 0.9
- [gh](https://cli.github.com/) CLI (authenticated)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- A [Nerd Font](https://www.nerdfonts.com/) for status icons

## Installation

### lazy.nvim

```lua
{
  "jayy-lmao/gh-review.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("gh-review").setup()
  end,
}
```

### From local path (development)

```lua
{
  dir = "~/Workspaces/gh-review.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("gh-review").setup()
  end,
}
```

## Commands

| Command | Description |
|---|---|
| `:GhPrList [mine\|others]` | Open Telescope picker with open PRs |
| `:GhPrComments [resolved\|unresolved]` | Browse PR comment threads |
| `:GhPrFiles` | Browse changed files in the current PR |
| `:GhPrToggle` | Toggle inline comment + diff overlays |
| `:GhPrRefresh` | Re-fetch PR data and re-render |
| `:GhPrAddComment` | Add a pending review comment on current line (or visual selection) |
| `:GhPrViewThread` | View the comment thread on current line |
| `:GhPrReply` | Reply to the thread on current line |
| `:GhPrNextComment` | Jump to next comment in file |
| `:GhPrPrevComment` | Jump to previous comment in file |
| `:GhPrReact` | React to the comment thread on current line |
| `:GhPrSubmitReview [approve\|comment\|request_changes]` | Submit pending review (prompts for type if omitted) |
| `:GhPrMerge` | Merge the current PR (merge / squash / rebase) |
| `:GhPrPending` | Show count of pending review comments |
| `:GhPrDiscardReview` | Discard all pending review comments |
| `:GhPrClear` | Clear all overlays and cached state |

## Keymaps

Default keymaps are enabled on setup. Disable with `keymaps = false` in config.

### Default Keymaps

| Key | Mode | Action |
|---|---|---|
| `<leader>gl` | n | PR list |
| `<leader>gf` | n | Changed files |
| `<leader>gc` | n | PR comments |
| `<leader>gt` | n | Toggle PR overlays |
| `<leader>gx` | n | Clear PR overlays |
| `<leader>ga` | n | Add review comment on line |
| `<leader>ga` | v | Add review comment on selection |
| `<leader>gv` | n | View thread |
| `<leader>gr` | n | Reply to thread |
| `]g` | n | Next PR comment |
| `[g` | n | Prev PR comment |
| `<leader>ge` | n | React to comment |
| `<leader>gs` | n | Submit review |
| `<leader>gd` | n | Discard pending review |
| `<leader>gp` | n | Pending comment count |
| `<leader>gm` | n | Merge PR |

### PR List Picker (`:GhPrList`)

| Key | Action |
|---|---|
| `<CR>` | Checkout PR branch and switch context |
| `<C-o>` | Open PR in browser |
| `<C-t>` | Cycle filter: mine / others / all |

### Changed Files Picker (`:GhPrFiles`)

| Key | Action |
|---|---|
| `<CR>` | Open file |
| `<C-v>` | Toggle viewed/unviewed status |

### Thread Viewer

| Key | Action |
|---|---|
| `q` | Close |
| `r` | Reply to thread |
| `R` | Resolve/unresolve thread |
| `e` | React to a comment |

### Reply / Add Comment

| Key | Action |
|---|---|
| `<C-s>` | Submit (normal or insert mode) |
| `q` | Cancel (normal mode) |

## Example Which-Key Config

```lua
lvim.builtin.which_key.mappings["G"] = {
  name = "+GitHub PR",
  a = { "<cmd>GhPrAddComment<cr>", "Add comment on line" },
  c = { "<cmd>GhPrComments<cr>", "List all comments" },
  d = { "<cmd>GhPrDiscardReview<cr>", "Discard pending review" },
  f = { "<cmd>GhPrFiles<cr>", "List changed files" },
  l = { "<cmd>GhPrList<cr>", "List open PRs" },
  M = { "<cmd>GhPrMerge<cr>", "Merge PR" },
  m = { "<cmd>GhPrList mine<cr>", "List my PRs" },
  n = { "<cmd>GhPrNextComment<cr>", "Next comment" },
  o = { "<cmd>GhPrList others<cr>", "List others' PRs" },
  p = { "<cmd>GhPrPrevComment<cr>", "Prev comment" },
  P = { "<cmd>GhPrPending<cr>", "Show pending count" },
  r = { "<cmd>GhPrReply<cr>", "Reply to thread on line" },
  R = { "<cmd>GhPrSubmitReview<cr>", "Submit review" },
  s = { "<cmd>GhPrComments resolved<cr>", "List resolved comments" },
  t = { "<cmd>GhPrToggle<cr>", "Toggle PR comments" },
  u = { "<cmd>GhPrComments unresolved<cr>", "List unresolved comments" },
  v = { "<cmd>GhPrViewThread<cr>", "View thread on line" },
  x = { "<cmd>GhPrClear<cr>", "Clear PR comments" },
}

-- Visual mode: comment on selected range
vim.keymap.set("v", "<leader>Ga", ":GhPrAddComment<cr>", { desc = "Add comment on selection" })

vim.keymap.set("n", "]g", "<cmd>GhPrNextComment<cr>")
vim.keymap.set("n", "[g", "<cmd>GhPrPrevComment<cr>")
```

## PR List Display

Each entry shows status icons from [gh-dash](https://github.com/dlvhdr/gh-dash) (Nerd Fonts):

```
 ● 󰄬 #123  @author  Add feature X        2d  1d
│ │ │  │      │       │                     │   │
│ │ │  │      │       │                     │   └── updated ago
│ │ │  │      │       │                     └────── created ago
│ │ │  │      │       └──────────────────────────── title
│ │ │  │      └──────────────────────────────────── author (hidden in "mine" filter)
│ │ │  └─────────────────────────────────────────── PR number
│ │ └────────────────────────────────────────────── review: 󰄬 approved / changes /  waiting
│ └──────────────────────────────────────────────── CI:  pass / 󰅙 fail /  pending
└────────────────────────────────────────────────── state:  open /  draft
```

## License

MIT
