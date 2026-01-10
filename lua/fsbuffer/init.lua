local fsb = {
	cfg = {
		border = "rounded",
		relative = "editor",
		width_ratio = 0.5,
		height_ratio = 0.5,
	},
	lines = {},
	cwd = nil,
	lines_idx_map = nil,
	name_maxwidth = 0,
	user_maxwidth = 0,
	cut_list = {},
	mode = "n",
	action = "normal",
	edit_range = { start_row = nil, end_row = nil },
	buf = nil,
	win = nil,
}
local format = require("fsbuffer.format")
local actions = require("fsbuffer.action")
setmetatable(actions, {
	__index = fsb,

	__newindex = function(_, key, value)
		fsb[key] = value
	end,
})

local ns_id = vim.api.nvim_create_namespace("fsbuffer_highlights")

function fsb:set_cfg()
	self.cfg.height = math.floor(vim.o.lines * self.cfg.height_ratio)
	self.cfg.width = math.floor(vim.o.columns * self.cfg.width_ratio)
	self.cfg.row = math.floor((vim.o.lines - self.cfg.height) / 2)
	self.cfg.col = math.floor((vim.o.columns - self.cfg.width) / 2)
end

function fsb:scan(cwd)
	self.name_maxwidth = 0
	self.user_maxwidth = 0
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

		local stat = vim.uv.fs_stat(cwd .. "/" .. name)
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
	self:watch()
	self:set_keymaps()
end

function fsb:update_root_dir_hightlight(path)
	vim.api.nvim_buf_set_extmark(self.buf, ns_id, 0, 0, {
		end_col = vim.api.nvim_strwidth(path),
		hl_group = "FsTitle",
	})
end

function fsb:update(root_dir, lines)
	-- clear buf text and extmarks
	vim.api.nvim_buf_set_lines(self.buf, 1, -1, false, {})
	local extmarks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, 0, -1, {})
	for _, mark in ipairs(extmarks) do
		vim.api.nvim_buf_del_extmark(self.buf, ns_id, mark[1])
	end

	if root_dir then
		self.cwd = root_dir
		self:scan(root_dir)
		-- render current path
		local path = ("~/%s/"):format(vim.fs.relpath(vim.env.HOME, root_dir))
		vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, { path })
		self:update_root_dir_hightlight(path)
	end

	lines = lines or self.lines
	for row, line in ipairs(lines) do
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
function fsb:render(dir)
	dir = dir or vim.uv.cwd()
	self:update(dir)

	local row = vim.api.nvim_win_get_cursor(0)[1]
	if row == 1 and #self.lines > 0 then
		vim.api.nvim_win_set_cursor(self.win, { 2, 0 })
	end
end

function fsb:set_keymaps()
	-- visual block
	vim.keymap.set("n", "<C-v>", function()
		self.mode = "\22"
		vim.print("set mode: \22")
		return "<C-v>"
	end, { noremap = true, buffer = true, expr = true })

	-- return normal
	vim.keymap.set({ "v", "i" }, "<esc>", function()
		self.mode = "n"
		return "<esc>"
	end, { noremap = true, buffer = true, expr = true })

	vim.keymap.set("n", "j", function()
		local row = vim.api.nvim_win_get_cursor(0)[1]

		if row == (1 + #self.lines) then
			vim.schedule(function()
				pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
			end)
			return ""
		else
			return "j"
		end
	end, { noremap = true, buffer = true, expr = true })

	vim.keymap.set("n", "k", function()
		local row = vim.api.nvim_win_get_cursor(0)[1]
		if row == 2 then
			vim.schedule(function()
				pcall(vim.api.nvim_win_set_cursor, 0, { #self.lines + 1, 0 })
			end)
			return ""
		end
		return "k"
	end, { noremap = true, buffer = true, expr = true })

	vim.keymap.set("n", "<backspace>", function()
		self:update(vim.fs.dirname(self.cwd))
	end, { noremap = true, buffer = true })

	vim.keymap.set("n", "/", function()
		self.mode = "c"
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_feedkeys("A", "n", false)
	end, { noremap = true, buffer = true })

	vim.api.nvim_buf_set_keymap(self.buf, "n", "<cr>", "", {
		callback = function()
			local row = vim.api.nvim_win_get_cursor(0)[1]
			local idx = row - 1
			if self.lines_idx_map then
				idx = self.lines_idx_map[row - 1]
			end
			if self.lines[idx].type == "directory" then
				self:update(self.cwd .. "/" .. self.lines[idx].name:gsub("/+$", ""))
			elseif self.lines[idx].type == "file" then
				vim.api.nvim_win_close(self.win, true)
				vim.cmd.edit(self.cwd .. "/" .. self.lines[idx].name)
			end
			self.lines_idx_map = nil
		end,
		noremap = true,
	})

	vim.api.nvim_buf_set_keymap(self.buf, "n", "o", "", {
		callback = function()
			self.action = "add"
			local row = vim.api.nvim_buf_line_count(self.buf)
			vim.api.nvim_buf_set_lines(self.buf, row, row, true, { "" })
			vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
			vim.cmd.startinsert()
		end,
		noremap = true,
	})

	vim.keymap.set({ "x", "n" }, "d", function()
		self.action = "cut"
		local start_row = vim.fn.getpos("v")[2]
		local end_row = vim.fn.getpos(".")[2]
		if start_row > end_row then
			start_row, end_row = end_row, start_row
		end
		for i = start_row, end_row, 1 do
			table.insert(self.cut_list, { path = self.cwd, name = self.lines[i - 1].name })
		end
		return "d"
	end, { noremap = true, buffer = true, expr = true })

	vim.keymap.set({ "x", "n" }, "p", function()
		if self.action == "cut" then
			self.action = "move"
			vim.schedule(function()
				actions:rename_and_render()
			end)
		elseif self.action == "yank" then
			self.action = "paste"
		end
		return "p"
	end, { noremap = true, buffer = true, expr = true })
end

function fsb:watch()
	vim.api.nvim_create_autocmd("TextChangedI", {
		buffer = self.buf,
		callback = function()
			-- search mode
			if self.mode == "c" then
				-- clear idx map
				self.lines_idx_map = nil
				local path = ("~/%s/"):format(vim.fs.relpath(vim.env.HOME, self.cwd))
				local text = vim.api.nvim_buf_get_lines(self.buf, 0, 1, true)[1]

				local search_path = (text:gsub("~", vim.env.HOME))
				local stat = vim.uv.fs_stat(search_path)
				if stat then
					if stat then
						self:update((search_path:gsub("/+$", "")))
					end
				elseif #text >= #path then
					local search_words = text:gsub(path, "")
					local total_valid_idx, total_idx = 1, 1
					self.lines_idx_map = {}

					self:update(
						nil,
						vim.tbl_filter(function(item)
							if string.find(item.name, search_words) then
								self.lines_idx_map[total_valid_idx] = total_idx
								total_valid_idx = total_valid_idx + 1
								total_idx = total_idx + 1
								return true
							end

							total_idx = total_idx + 1
							return false
						end, self.lines)
					)
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = self.buf,
		callback = function()
			if self.mode == "c" then
				return
			end
			local row = vim.api.nvim_win_get_cursor(0)[1]
			if row == 1 and #self.lines > 0 then
				pcall(vim.api.nvim_win_set_cursor, self.win, { 2, 0 })
			end
		end,
	})

	vim.api.nvim_create_autocmd("InsertEnter", {
		buffer = self.buf,
		callback = function()
			if self.mode == "c" then
				return
			end
			if self.mode ~= "\22" then
				-- local row = vim.api.nvim_win_get_cursor(0)[1]

				-- vim.print(self.lines[row - 1].name)
				-- vim.print(vim.api.nvim_buf_get_lines(self.buf, row - 1, row, true))
				-- vim.print(vim.fn.getline(row))
			end
		end,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		buffer = self.buf,
		callback = function()
			if self.mode == "c" then
				return
			end
			if self.mode ~= "\22" then
				-- update root dir
				local path = ("~/%s/"):format(vim.fs.relpath(vim.env.HOME, self.cwd))
				local text = vim.api.nvim_buf_get_lines(self.buf, 0, 1, true)[1]
				if #text < #path then
					vim.api.nvim_buf_set_text(0, 0, 0, 0, -1, { path })
				end
				self:update_root_dir_hightlight(path)

				-- create
				if self.action == "add" then
					actions:create_and_render()
				elseif self.action == "cut" then
				end
				-- local row = vim.api.nvim_win_get_cursor(0)[1]
				-- vim.print(vim.fn.getline(row))

				-- vim.print(self.lines[row - 1].name)
				-- vim.print(vim.api.nvim_buf_get_lines(self.buf, row - 1, row, true))
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		buffer = self.buf,
		callback = function()
			self.edit_range = { start_row = nil, end_row = nil }
		end,
	})
end

return fsb
