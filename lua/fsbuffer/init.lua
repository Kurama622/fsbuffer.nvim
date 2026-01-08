local fsb = {
	cfg = {
		border = "rounded",
		relative = "editor",
		width_ratio = 0.6,
		height_ratio = 0.5,
	},
	lines = {},
	cwd = vim.uv.cwd(),
	name_maxwidth = 0,
	user_maxwidth = 0,
	mode = "normal",
	buf = nil,
	win = nil,
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
				["name"] = t == "directory" and name .. "/" or name,
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
	self.buf = vim.api.nvim_create_buf(false, true)
	self.win = vim.api.nvim_open_win(self.buf, true, {
		relative = self.cfg.relative,
		border = self.cfg.border,
		row = self.cfg.row,
		col = self.cfg.col,
		height = self.cfg.height,
		width = self.cfg.width,
	})

	vim.wo[self.win].number = false
	vim.wo[self.win].relativenumber = false
	vim.wo[self.win].signcolumn = "no"
	vim.wo[self.win].spell = false
	vim.bo[self.buf].filetype = "fsbuffer"

	vim.cmd.syntax('match FsDir "[^[:space:]]\\+/"')
	self:render()
end

function fsb:render()
	self:scan(self.cwd)
	-- render current path
	local path = ("~/%s/"):format(vim.fs.relpath(vim.env.HOME, self.cwd))
	vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, { path })
	vim.api.nvim_buf_set_extmark(self.buf, ns_id, 0, 0, {
		end_col = vim.api.nvim_strwidth(path),
		hl_group = "FsTitle",
	})

	for row, line in ipairs(self.lines) do
		vim.api.nvim_buf_set_lines(
			self.buf,
			row,
			row,
			false,
			{ ("%-" .. (self.name_maxwidth + 2) .. "s"):format(line.name) }
		)

		local texts = {
			{ ("%-11s "):format(line.mode), "FsMode" },
			{ ("%-" .. (self.user_maxwidth + 2) .. "s "):format(line.username), "FsUser" },
			{ ("%-10s "):format(line.size), "FsSize" },
			{ ("%-20s "):format(line.date), "FsDate" },
		}
		vim.api.nvim_buf_set_extmark(self.buf, ns_id, row, 0, {
			hl_mode = "combine",
			virt_text = texts,
			right_gravity = false,
		})
	end
end

return fsb
