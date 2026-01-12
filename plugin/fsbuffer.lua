if vim.g.loaded_fsb then
	return
end
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_fsb = true

local highlight = {
	FsTitle = { fg = "#2aa198", bold = true, default = true },
	FsDir = { fg = "#84a800", default = true },
	FsMode = { fg = "#4c566a", default = true },
	FsSize = { fg = "#4c566a", default = true },
	FsUser = { fg = "#d08770", default = true },
	FsDate = { fg = "#4c566a", default = true },
}

for k, v in pairs(highlight) do
	vim.api.nvim_set_hl(0, k, v)
end

local fsb = require("fsbuffer")

vim.api.nvim_create_user_command("Fsbuffer", function(args)
	fsb:toggle(args.fargs[1])
end, { nargs = "?", range = true })

vim.keymap.set("n", "<leader>fs", function()
	vim.cmd.Fsbuffer()
end)
