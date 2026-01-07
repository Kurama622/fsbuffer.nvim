local fsb = {
	cfg = {
		border = "rounded",
		relative = "editor",
		width_ratio = 0.6,
		height_ratio = 0.5,
	},
	lines = {},
	cwd = "",
	name_maxwidth = 0,
	user_maxwidth = 0,
}
local format = require("fsbuffer.format")

local ns_id = vim.api.nvim_create_namespace("fsbuffer_highlights")

function fsb:set_cfg()
	self.cfg.height = math.floor(vim.o.lines * self.cfg.height_ratio)
	self.cfg.width = math.floor(vim.o.columns * self.cfg.width_ratio)
	self.cfg.row = math.floor((vim.o.lines - self.cfg.height) / 2)
	self.cfg.col = math.floor((vim.o.columns - self.cfg.width) / 2)
end

function fsb:scan(cwd)
	self.lines = {}
	local uv = vim.uv or vim.loop

	local handle = uv.fs_scandir(cwd)
	if not handle then
		return
	end

	while true do
		local name, t = uv.fs_scandir_next(handle)
		if not name then
			break
		end
		local stat = uv.fs_stat(name)
		if stat then
			self.name_maxwidth = math.max(self.name_maxwidth, vim.api.nvim_strwidth(name))
			local username = format.username(stat.uid)
			self.user_maxwidth = math.max(self.user_maxwidth, vim.api.nvim_strwidth(username))

			table.insert(self.lines, {
				["name"] = name,
				["type"] = t,
				["mode"] = format.permissions(stat.mode),
				["size"] = format.size(stat.size),
				["username"] = username,
				["date"] = format.friendly_time(stat.mtime.sec),
			})
		end
	end
end

function fsb:create()
	self.cwd = vim.uv.cwd()
	self:scan(self.cwd)

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = self.cfg.relative,
		border = self.cfg.border,
		row = self.cfg.row,
		col = self.cfg.col,
		height = self.cfg.height,
		width = self.cfg.width,
	})

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].spell = false
	vim.bo[buf].filetype = "fsbuffer"

	vim.api.nvim_buf_set_lines(buf, 0, 1, true, { self.cwd })
	for row, line in ipairs(self.lines) do
		vim.api.nvim_buf_set_lines(
			buf,
			row,
			row,
			false,
			{ ("%-" .. (self.name_maxwidth + 2) .. "s"):format(line.name) }
		)

		local texts = {
			{ ("%-11s "):format(line.mode), "comment" },
			{ ("%-" .. (self.user_maxwidth + 2) .. "s "):format(line.username), "keyword" },
			{ ("%-10s "):format(line.size), "string" },
			{ ("%-20s "):format(line.date), "title" },
		}
		vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
			hl_mode = "combine",
			virt_text = texts,
			right_gravity = false,
		})
	end
end

return fsb
