# fsbuffer.nvim

Support fuzzy search

https://github.com/user-attachments/assets/5e2b1baa-6d1a-4093-a269-6cda6fb8785c

## Installation

```lua
  {
    "Kurama622/fsbuffer.nvim",
    cmd = "Fsbuffer",
    opts = {
      search = {
        -- none | fd | fzf-fd
        -- fd depends on: https://github.com/sharkdp/fd
        -- fzf-fd depends on: 
        --    1. https://github.com/sharkdp/fd
        --    2. https://github.com/junegunn/fzf
        cmd = "fd",
      },
    },
    keys = {
      {
        "<leader>e",
        function()
          require("fsbuffer"):toggle(vim.fn.expand("%:p:h") .. "/")
        end,
        desc = "Fsbuffer (Current Buffer Dir)",
      },
      {
        "<leader>E",
        function()
          require("fsbuffer"):toggle(vim.fs.root(0, ".git") .. "/")
        end,
        desc = "Fsbuffer (Root Dir)",
      },
    },
  }
```

`:Fsbuffer` or use shortcut keys

## Keymaps


| key              | mode            | action                                             |
| ---              | ----            | ------                                             |
| `j` / `Ctrl-j`   | `n`             | mode down                                          |
| `k` / `Ctrl-k`   | `n`             | mode up                                            |
| `/`              | `n`             | search                                             |
| `o` / `O`        | `n`             | create files or dirs                               |
| `<CR>`           | `n`             | enter a dir or open a file                         |
| `<CR>`           | `i` (in search) | choose the first item in the list to enter or open |
| `<backspace>`    | `n`             | enter the parent dir                               |
| `d`: Same as vim | `n`/`v`         | cut, save the buffer then delete                   |
| `y`: Same as vim | `n`/`v`         | copy                                               |
| `p` / `P`        | `n`             | paste                                              |
| `:`              | `n`             | cmdline                                            |
| `Ctrl-j`         | `i`             | exit search                                        |

## Reference

- [dired.nvim](https://github.com/nvimdev/dired.nvim)
