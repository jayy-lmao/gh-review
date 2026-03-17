# gh-review.nvim

A Neovim plugin for reviewing GitHub pull requests without leaving your editor. Browse PRs, view inline comments with diff context, reply to threads, and manage file review state — all powered by the `gh` CLI.

## Features

- **PR List** — Telescope picker showing open PRs with colored status icons (CI, review, draft state), filterable by author
- **Inline Comments** — Virtual text overlays showing PR review threads directly on your source code
- **Diff Highlighting** — Inline diff rendering (additions/deletions) against the base branch
- **File Review** — Browse changed files with viewed/unviewed status, toggle with a keypress
- **Thread Actions** — View, reply to, resolve/unresolve comment threads from floating windows
- **PR Checkout** — Check out any PR branch directly from the picker

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
| `:GhPrAddComment` | Add a new review comment on current line |
| `:GhPrViewThread` | View the comment thread on current line |
| `:GhPrReply` | Reply to the thread on current line |
| `:GhPrNextComment` | Jump to next comment in file |
| `:GhPrPrevComment` | Jump to previous comment in file |
| `:GhPrClear` | Clear all overlays and cached state |

## Keymaps

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
  f = { "<cmd>GhPrFiles<cr>", "List changed files" },
  l = { "<cmd>GhPrList<cr>", "List open PRs" },
  m = { "<cmd>GhPrList mine<cr>", "List my PRs" },
  n = { "<cmd>GhPrNextComment<cr>", "Next comment" },
  o = { "<cmd>GhPrList others<cr>", "List others' PRs" },
  p = { "<cmd>GhPrPrevComment<cr>", "Prev comment" },
  r = { "<cmd>GhPrReply<cr>", "Reply to thread on line" },
  s = { "<cmd>GhPrComments resolved<cr>", "List resolved comments" },
  t = { "<cmd>GhPrToggle<cr>", "Toggle PR comments" },
  u = { "<cmd>GhPrComments unresolved<cr>", "List unresolved comments" },
  v = { "<cmd>GhPrViewThread<cr>", "View thread on line" },
  x = { "<cmd>GhPrClear<cr>", "Clear PR comments" },
}

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
