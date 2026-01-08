if vim.g.loaded_fsb then
	return
end

vim.g.loaded_fsb = true

local fsb = require("fsbuffer")

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
fsb:set_cfg()
vim.keymap.set("n", "<leader>fs", function()
	fsb:create()
end)
