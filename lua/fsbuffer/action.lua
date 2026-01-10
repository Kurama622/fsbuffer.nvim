local actions = {}
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
	self:update(self.cwd)
end

function actions:rename_and_render()
	for _, item in ipairs(self.cut_list) do
		vim.uv.fs_rename(item.path .. "/" .. item.name, self.cwd .. "/" .. item.name)
	end
	self.cut_list = {}
	self:update(self.cwd)
end

function actions:remove_and_render()
	for _, item in ipairs(self.cut_list) do
		if item.type == "directory" then
			vim.uv.fs_rmdir(item.path .. "/" .. item.name)
		elseif item.type == "file" then
			vim.uv.fs_unlink(item.path .. "/" .. item.name)
		end
	end

	self.cut_list = {}
end
return actions
