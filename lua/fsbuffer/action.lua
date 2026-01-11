local actions = {}

function actions:range()
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")
	local start_row, start_col = start_pos[2], start_pos[3]
	local end_row, end_col = end_pos[2], end_pos[3]

	if start_row > end_row or (start_row == end_row and start_col > end_col) then
		start_row, end_row = end_row, start_row
		start_col, end_col = end_col, start_col
	end
	return start_row, end_row, start_col, end_col
end

function actions:visual_range()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local start_row, start_col = start_pos[2], start_pos[3]
	local end_row, end_col = end_pos[2], end_pos[3]

	if start_row > end_row or (start_row == end_row and start_col > end_col) then
		start_row, end_row = end_row, start_row
		start_col, end_col = end_col, start_col
	end
	return start_row, end_row, start_col, end_col
end

function actions:create_dir(base_dir, path)
	vim.uv.fs_mkdir(base_dir .. "/" .. path, 493)
end
function actions:create_file(base_dir, path)
	vim.uv.fs_open(base_dir .. "/" .. path, "w", 438)
end

function actions:create_dir_recursive(path)
	local parts = vim.split(path, "/", { plain = true, trimempty = true })
	local base_dir = self.cwd

	for _, part in ipairs(parts) do
		self:create_dir(base_dir, part)
		base_dir = base_dir .. "/" .. part
	end
end

function actions:create_file_recursive(path)
	local parts = vim.split(path, "/", { plain = true, trimempty = true })
	local base_dir = self.cwd

	for i, part in ipairs(parts) do
		if i == #parts then
			self:create_file(base_dir, part)
		else
			self:create_dir(base_dir, part)
			base_dir = base_dir .. "/" .. part
		end
	end
end

function actions:create_and_render()
	local name = vim.api.nvim_get_current_line()
	if name:match("/$") then
		actions:create_dir_recursive(name)
	else
		actions:create_file_recursive(name)
	end
	self.action = "normal"
	self:update(self.cwd)
end

function actions:rename(i, text, new_text)
	vim.uv.fs_rename(text, new_text, function(err)
		if err then
			vim.print(err)
		end
		table.remove(self.cut_list, i)
		if vim.tbl_isempty(self.cut_list) then
			vim.schedule(function()
				self:update(self.cwd)
			end)
		end
	end)
end

function actions:rename_all(t)
	for i, item in ipairs(t) do
		self:rename(i, item.path .. "/" .. item.name, self.cwd .. "/" .. item.name)
	end
end

function actions:remove_all(t)
	for i, item in ipairs(t) do
		if item.type == "directory" then
			local function remove_dir(dir)
				vim.uv.fs_rmdir(dir, function(err)
					if err then
						local handle = vim.uv.fs_scandir(dir)
						if not handle then
							return
						end

						while true do
							local name, type = vim.uv.fs_scandir_next(handle)
							if not name then
								break
							end

							local p = dir .. "/" .. name

							if type == "directory" then
								remove_dir(p)
							else
								vim.uv.fs_unlink(p)
							end
						end
					end
					remove_dir(dir)
					table.remove(t, i)
					if vim.tbl_isempty(t) then
						vim.schedule(function()
							self:update(self.cwd)
						end)
					end
				end)
			end
			remove_dir(item.path .. "/" .. item.name)
		elseif item.type == "file" then
			vim.uv.fs_unlink(item.path .. "/" .. item.name, function(err)
				if err then
					vim.print(err)
				end
				table.remove(t, i)
				if vim.tbl_isempty(t) then
					vim.schedule(function()
						self:update(self.cwd)
					end)
				end
			end)
		end
	end
end

function actions:paste_all(t)
	for _, item in ipairs(t) do
		local src = item.path .. "/" .. item.name
		local desc = self.cwd .. "/" .. item.name
		if src == desc then
			desc = self.cwd .. "/_" .. item.name
		end
		if item.type == "directory" then
			local function copy_dir(source, dest)
				local stat = vim.uv.fs_stat(source)
				if not stat then
					vim.print("The dir does not exist: " .. source)
					return
				end

				vim.uv.fs_mkdir(dest, stat.mode)

				local handle = vim.uv.fs_scandir(source)
				if not handle then
					return
				end

				while true do
					local name, type = vim.uv.fs_scandir_next(handle)
					if not name then
						break
					end

					local src_path = source .. "/" .. name
					local dest_path = dest .. "/" .. name

					if type == "directory" then
						copy_dir(src_path, dest_path)
					else
						vim.uv.fs_copyfile(src_path, dest_path)
					end
				end
			end
			copy_dir(src, desc)
		elseif item.type == "file" then
			vim.uv.fs_copyfile(src, desc)
		end
	end

	self.yank_list = {}
	self:update(self.cwd)
end

return actions
