local fsb = {
	exist = false,
	lines = {},
	cwd = nil,
	lines_idx_map = nil,
	max_name_width = 0,
	max_user_width = 0,
	max_date_width = 0,
	cut_list = {},
	yank_list = {},
	mode = "n",
	action = "normal",
	edit = { range = { start_row = nil, end_row = nil, start_col = nil, end_col = nil }, texts = {}, modified = false },
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

function fsb.setup(opts)
	fsb.cfg = vim.tbl_deep_extend("force", require("fsbuffer.config"), opts)
end

function fsb:init_window_config()
	if self.cfg == nil then
		self.cfg = require("fsbuffer.config")
	end
	self.cfg.height = self.cfg.height or math.floor(vim.o.lines * self.cfg.height_ratio)
	self.cfg.width = math.min(
		self.cfg.max_window_width,
		math.max(
			vim.api.nvim_strwidth(self.cwd) - vim.api.nvim_strwidth(vim.env.HOME) + 2,
			self.max_name_width + self.max_user_width + self.max_date_width + 33
		)
	)
	self.cfg.row = self.cfg.row or math.floor((vim.o.lines - self.cfg.height) / 2)
	self.cfg.col = self.cfg.col or math.floor((vim.o.columns - self.cfg.width) / 2)
end

function fsb:update_window()
	if self.win then
		self.cfg.width = math.max(
			vim.api.nvim_strwidth(self.cwd) - vim.api.nvim_strwidth(vim.env.HOME) + 2,
			self.max_name_width + self.max_user_width + self.max_date_width + 33
		)
		self.cfg.col = math.floor((vim.o.columns - self.cfg.width) / 2)
		vim.api.nvim_win_set_config(self.win, {
			relative = self.cfg.relative,
			border = self.cfg.border,
			row = self.cfg.row,
			col = self.cfg.col,
			height = self.cfg.height,
			width = self.cfg.width,
		})
	end
end

function fsb:close()
	vim.api.nvim_win_close(self.win, true)

	self.edit = {
		range = { start_row = nil, end_row = nil, start_col = nil, end_col = nil },
		texts = {},
		modified = false,
	}
	self.exist = false
	self.win, self.buf = nil, nil
end

function fsb:create_fs_buffer(dir)
	self.buf = vim.api.nvim_create_buf(false, true)
	dir = dir or vim.uv.cwd()
	self:update_buffer_render(dir)
end

function fsb:create_fs_window()
	self:init_window_config()
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
	vim.bo[self.buf].buftype = "acwrite"
	vim.bo[self.buf].bufhidden = "wipe"
	vim.bo[self.buf].swapfile = false

	vim.api.nvim_buf_set_name(self.buf, "fsbuffer")
	vim.cmd.syntax('match FsDir "[^[:space:]]\\+/"')
	local row = vim.api.nvim_win_get_cursor(0)[1]
	if row == 1 and #self.lines > 0 then
		vim.api.nvim_win_set_cursor(self.win, { 2, 0 })
	end
end

function fsb:toggle(dir)
	if self.exist then
		self:close()
		return
	end

	self:create_fs_buffer(dir)
	self:create_fs_window()

	self:watch()
	self:set_keymaps()

	self.exist = true
end

function fsb:update_root_dir_hightlight(path)
	vim.api.nvim_buf_set_extmark(self.buf, ns_id, 0, 0, {
		end_col = vim.api.nvim_strwidth(path),
		hl_group = "FsTitle",
	})
end

function fsb:scan(cwd)
	self.max_name_width = 0
	self.max_user_width = 0
	self.max_date_width = 0
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
			self.max_name_width = math.max(self.max_name_width, vim.api.nvim_strwidth(name))
			local username = format.username(stat.uid) or "nil"
			self.max_user_width = math.max(self.max_user_width, vim.api.nvim_strwidth(username))
			local date = format.friendly_time(stat.mtime.sec) or "nil"
			self.max_date_width = math.max(self.max_date_width, vim.api.nvim_strwidth(date))

			table.insert(self.lines, {
				["name"] = t == "directory" and name .. "/" or name,
				["type"] = t,
				["mode"] = format.permissions(stat.mode),
				["size"] = format.size(stat.size),
				["username"] = username,
				["date"] = date,
				["dired"] = false,
			})
		end
	end
	self:update_window()
end

function fsb:update_buffer_render(root_dir, lines, keep_title)
	if self.buf == nil then
		return
	end
	-- clear buf text and extmarks
	vim.api.nvim_buf_set_lines(self.buf, 1, -1, false, {})
	local extmarks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, 0, -1, {})
	for _, mark in ipairs(extmarks) do
		vim.api.nvim_buf_del_extmark(self.buf, ns_id, mark[1])
	end

	if root_dir then
		self.cwd = root_dir
		self:scan(root_dir)
	end

	-- render current path
	local path = self.cwd
	if vim.startswith(path, vim.env.HOME) then
		path = "~" .. path:sub(#vim.env.HOME + 1) .. "/"
	end
	if not keep_title then
		vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, { path })
	end
	self:update_root_dir_hightlight(path)

	lines = lines or self.lines
	for row, line in ipairs(lines) do
		vim.api.nvim_buf_set_lines(
			self.buf,
			row,
			row,
			false,
			{ ("%-" .. (self.max_name_width + 2) .. "s"):format(line.name) }
		)

		local status = line.dired and " *" or "  "
		lines[row].dired_id = vim.api.nvim_buf_set_extmark(self.buf, ns_id, row, 0, {
			virt_text = { { status, "FsTitle" } },
			virt_text_pos = "inline",
		})

		local texts = {
			{ ("%-11s "):format(line.mode), "FsMode" },
			{ ("%-" .. (self.max_user_width + 2) .. "s "):format(line.username), "FsUser" },
			{ ("%-10s "):format(line.size), "FsSize" },
			{ ("%-" .. (self.max_date_width + 2) .. "s "):format(line.date), "FsDate" },
		}
		vim.api.nvim_buf_set_extmark(self.buf, ns_id, row, 0, {
			hl_mode = "combine",
			virt_text = texts,
			right_gravity = false,
		})
	end

	if vim.tbl_isempty(self.cut_list) then
		vim.bo[self.buf].modified = false
	end
end

function fsb:set_keymaps()
	-- visual block
	vim.keymap.set("n", "<C-v>", function()
		self.mode = "\22"
		return "<C-v>"
	end, { noremap = true, buffer = true, expr = true })

	vim.keymap.set("n", "v", function()
		self.mode = "v"
		return "v"
	end, { noremap = true, buffer = true, expr = true })

	vim.keymap.set("n", "V", function()
		self.mode = "V"
		return "V"
	end, { noremap = true, buffer = true, expr = true })

	-- return normal
	vim.keymap.set({ "v", "i" }, "<esc>", function()
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
		self:update_buffer_render(vim.fs.dirname(self.cwd))
	end, { noremap = true, buffer = true })

	vim.keymap.set("n", "/", function()
		self.mode = "c"
		self.action = "normal"
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
				self:update_buffer_render(self.cwd .. "/" .. self.lines[idx].name:gsub("/+$", ""))
			elseif self.lines[idx].type == "file" then
				self:close()
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

	vim.keymap.set({ "x", "o" }, "d", function()
		local mode = vim.api.nvim_get_mode().mode
		if mode == "no" or mode == "V" then
			if not vim.tbl_isempty(self.cut_list) then
				vim.print("Unprocessed files or folders:", self.cut_list)
				return
			end
			self.action = "cut"

			local start_row, end_row = actions:range()
			for i = start_row, end_row, 1 do
				table.insert(
					self.cut_list,
					{ path = self.cwd, name = self.lines[i - 1].name, ["type"] = self.lines[i - 1].type }
				)
				self.lines[i - 1].dired = true
			end
			vim.schedule(function()
				local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
				vim.api.nvim_feedkeys(esc, "n", false)
				self:update_buffer_render()
			end)
		elseif mode == "\22" then
			vim.schedule(function()
				vim.cmd.Edit()
				for idx = self.edit.range.start_row, self.edit.range.end_row, 1 do
					vim.api.nvim_buf_set_text(
						self.buf,
						idx - 1,
						self.edit.range.start_col - 1,
						idx - 1,
						self.edit.range.end_col,
						{}
					)
				end
				self.edit.modified = true
				vim.cmd.Rename()
				local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
				vim.api.nvim_feedkeys(esc, "n", false)
			end)
		end
	end, { noremap = true, buffer = true })

	vim.keymap.set({ "x", "n" }, "y", function()
		self.action = "yank"
		local start_row, end_row = actions:range()
		for i = start_row, end_row, 1 do
			table.insert(
				self.yank_list,
				{ path = self.cwd, name = self.lines[i - 1].name, ["type"] = self.lines[i - 1].type }
			)
		end
		return "y"
	end, { noremap = true, buffer = true, expr = true })

	vim.keymap.set({ "x", "n" }, "p", function()
		self.action = "paste"
		vim.schedule(function()
			actions:rename_all(self.cut_list)
			actions:paste_all(self.yank_list)
		end)
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

				local path = self.cwd
				if vim.startswith(path, vim.env.HOME) then
					path = "~" .. path:sub(#vim.env.HOME + 1) .. "/"
				end
				local text = vim.api.nvim_buf_get_lines(self.buf, 0, 1, true)[1]

				local search_path = (text:gsub("~", vim.env.HOME))
				local stat = vim.uv.fs_stat(search_path)
				if stat then
					self:update_buffer_render((search_path:gsub("/+$", "")))
				elseif #text >= #path then
					local search_words = text:gsub(path, "")
					local total_valid_idx, total_idx = 1, 1
					self.lines_idx_map = {}

					self:update_buffer_render(
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
						end, self.lines),
						true
					)
				end
			elseif not vim.tbl_isempty(self.edit.texts) then
				self.edit.modified = true
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

			local action_range = function()
				return actions:visual_range()
			end

			-- visual block需要特殊处理
			if self.mode ~= "\22" then
				action_range = function()
					return actions:range()
				end
				self.mode = "i"
			end

			if self.action ~= "add" then
				local start_row, end_row = action_range()
				for i = start_row, end_row, 1 do
					vim.api.nvim_buf_del_extmark(0, ns_id, self.lines[i - 1].dired_id)
				end
			end
			vim.cmd.Edit()
		end,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		buffer = self.buf,
		callback = function()
			if self.mode == "c" then
				self.mode = "n"
				-- update root dir
				local path = self.cwd
				if vim.startswith(path, vim.env.HOME) then
					path = "~" .. path:sub(#vim.env.HOME + 1) .. "/"
				end
				local text = vim.api.nvim_buf_get_lines(self.buf, 0, 1, true)[1]
				if #text < #path then
					vim.api.nvim_buf_set_text(0, 0, 0, 0, -1, { path })
				end
				self:update_root_dir_hightlight(path)

				return
			end

			vim.cmd.Rename()
			self.mode = "n"

			-- create
			if self.action == "add" then
				actions:create_and_render()
			end
		end,
	})

	vim.api.nvim_buf_create_user_command(self.buf, "Edit", function()
		if self.action == "add" then
			return
		end
		self.edit =
			{ range = { start_row = nil, end_row = nil, start_col = nil, end_col = nil }, texts = {}, modified = false }
		local mode = vim.api.nvim_get_mode().mode
		if mode == "\22" or mode == "v" or mode == "V" or self.mode == "i" then
			self.edit.range.start_row, self.edit.range.end_row, self.edit.range.start_col, self.edit.range.end_col =
				actions:range()
		else
			self.edit.range.start_row, self.edit.range.end_row, self.edit.range.start_col, self.edit.range.end_col =
				actions:visual_range()
		end

		for i = self.edit.range.start_row, self.edit.range.end_row, 1 do
			table.insert(self.edit.texts, self.lines[i - 1].name)
		end
	end, {})

	vim.api.nvim_buf_create_user_command(self.buf, "Rename", function()
		if not vim.tbl_isempty(self.edit.texts) then
			if self.mode == "\22" then
				if not self.edit.modified then
					self:update_buffer_render()
				end
				vim.api.nvim_create_autocmd("TextChanged", {
					buffer = self.buf,
					once = true,
					callback = function()
						if not self.edit.modified then
							self:update_buffer_render()
							return
						end

						local new_texts = vim.api.nvim_buf_get_lines(
							self.buf,
							self.edit.range.start_row - 1,
							self.edit.range.end_row,
							true
						)

						for i, raw_text in ipairs(self.edit.texts) do
							actions:rename(
								i,
								self.cwd .. "/" .. (raw_text:gsub("%s+$", "")),
								self.cwd .. "/" .. (new_texts[i]:gsub("%s+$", ""))
							)
						end
						self.edit = {
							range = { start_row = nil, end_row = nil, start_col = nil, end_col = nil },
							texts = {},
							modified = false,
						}
						self.mode = "n"
					end,
				})
			else
				if not self.edit.modified then
					self:update_buffer_render()
					return
				end
				local new_texts =
					vim.api.nvim_buf_get_lines(self.buf, self.edit.range.start_row - 1, self.edit.range.end_row, true)
				for i, raw_text in ipairs(self.edit.texts) do
					actions:rename(
						i,
						self.cwd .. "/" .. (raw_text:gsub("%s+$", "")),
						self.cwd .. "/" .. (new_texts[i]:gsub("%s+$", ""))
					)
				end
				self.edit = {
					range = { start_row = nil, end_row = nil, start_col = nil, end_col = nil },
					texts = {},
					modified = false,
				}
				self:update_buffer_render(self.cwd)
				self.mode = "n"
			end
		end
	end, {})

	vim.api.nvim_create_autocmd("WinClosed", {
		buffer = self.buf,
		callback = function()
			self:close()
		end,
	})

	vim.api.nvim_create_autocmd({ "QuitPre", "BufWriteCmd" }, {
		pattern = "fsbuffer",
		callback = function()
			actions:remove_all(self.cut_list)
			vim.bo[self.buf].modified = false
		end,
	})
end

return fsb
