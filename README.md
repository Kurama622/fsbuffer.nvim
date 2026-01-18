# fsbuffer.nvim

https://github.com/user-attachments/assets/5e2b1baa-6d1a-4093-a269-6cda6fb8785c

## Installation

```lua
  {
    "Kurama622/fsbuffer.nvim",
    cmd = "Fsbuffer",
    opts = {
      search = {
        -- none | fd
        -- fd depends on: https://github.com/sharkdp/fd
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

## Reference

- [dired.nvim](https://github.com/nvimdev/dired.nvim)
