# fsbuffer.nvim

## Install

```lua
{
    "Kurama622/fsbuffer.nvim",
    opts = {
      search = {
        cmd = "fd", -- none/fd
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

## Reference

- [dired.nvim](https://github.com/nvimdev/dired.nvim)
