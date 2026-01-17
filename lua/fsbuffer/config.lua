return {
  border = "rounded",
  relative = "editor",
  height_ratio = 0.5,
  max_window_width = math.floor(vim.o.columns * 0.8),
  indicator = "󰧞",
  delete_the_cut_on_close = false,
  search = {
    cmd = "none", -- none, fd
    ignore = { ".git" },
  },
  keymap = {
    enter_parent_dir = "<backspace>",
    open = "<cr>",
  },
}
