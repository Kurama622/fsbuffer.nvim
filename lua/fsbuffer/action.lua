local actions = {}

local format = require("fsbuffer.format")
local log = require("fsbuffer.log")

local function tbl_remove_elements(t, indices)
  table.sort(indices, function(a, b)
    return a > b
  end)

  for _, i in ipairs(indices) do
    table.remove(t, i)
  end
end

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

function actions:update_path_detail(cwd, name)
  local stat = vim.uv.fs_stat(cwd .. "/" .. name)
  if stat then
    self.max_name_width = math.max(self.max_name_width, #name)
    local username = format.username(stat.uid) or "nil"
    self.max_user_width = math.max(self.max_user_width, #username)
    local date = format.friendly_time(stat.mtime.sec) or "nil"
    self.max_date_width = math.max(self.max_date_width, #date)
  end
end

function actions:query_path_detail(cwd, name)
  local stat = vim.uv.fs_stat(cwd .. "/" .. name)
  if stat then
    local t = stat.type
    self.max_name_width = math.max(self.max_name_width, #name)
    local username = format.username(stat.uid) or "nil"
    self.max_user_width = math.max(self.max_user_width, #username)
    local date = format.friendly_time(stat.mtime.sec) or "nil"
    self.max_date_width = math.max(self.max_date_width, #date)

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

function actions:create_dir(base_dir, path)
  vim.uv.fs_mkdir(base_dir .. "/" .. path, 493)
end
function actions:create_file(base_dir, path)
  vim.uv.fs_open(base_dir .. "/" .. path, "w", 438)
end

function actions:create_dir_recursive(path)
  local parts = vim.split(path, "/", { plain = true, trimempty = true })
  local base_dir = self.cwd

  for i, part in ipairs(parts) do
    self:create_dir(base_dir, part)
    if i == 1 then
      self:query_path_detail(self.cwd, part)
    end
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
    if i == 1 then
      self:query_path_detail(self.cwd, part)
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

  self:update_buffer_render()
end

function actions:rename(idx, raw_dir, text, new_text)
  local t = "file"
  if new_text:sub(-1) == "/" then
    t = "directory"
    new_text = new_text:sub(1, -2)
  end
  vim.uv.fs_rename(raw_dir .. "/" .. text, self.cwd .. "/" .. new_text, function(err)
    if err then
      log.error(err)
    end
    if raw_dir == self.cwd then
      self.lines[idx].name = t == "directory" and new_text .. "/" or new_text
      self.lines[idx].dired = false

      -- only update the current directory/file
      self:update_path_detail(self.cwd, new_text)
    else
      self:query_path_detail(self.cwd, new_text)
    end
    table.remove(self.cut_list, 1)
    if vim.tbl_isempty(self.cut_list) then
      vim.schedule(function()
        self:update_buffer_render()
      end)
    end
  end)
end

function actions:rename_all(t)
  for _, item in ipairs(t) do
    self:rename(item.idx, item.path, item.name, item.name)
  end
end

function actions:remove_all(t)
  local indices = vim.tbl_map(function(item)
    return item.idx
  end, t)
  for _, item in ipairs(t) do
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
            remove_dir(dir)
          else
            table.remove(t, 1)
            if vim.tbl_isempty(t) then
              tbl_remove_elements(self.lines, indices)
              vim.schedule(function()
                self:update_buffer_render()
              end)
            end
          end
        end)
      end
      remove_dir(item.path .. "/" .. item.name)
    elseif item.type == "file" then
      vim.uv.fs_unlink(item.path .. "/" .. item.name, function(err)
        if err then
          log.error(err)
        end
        table.remove(t, 1)
        if vim.tbl_isempty(t) then
          tbl_remove_elements(self.lines, indices)
          vim.schedule(function()
            self:update_buffer_render()
          end)
        end
      end)
    end
  end
end

function actions:paste_all(t)
  for _, item in ipairs(t) do
    local basename = item.type == "directory" and item.name:sub(1, -2) or item.name
    local src = item.path .. "/" .. basename
    local desc = self.cwd .. "/" .. basename
    if src == desc then
      desc = self.cwd .. "/_" .. basename
      basename = "_" .. basename
    end
    if item.type == "directory" then
      local function copy_dir(source, dest)
        local stat = vim.uv.fs_stat(source)
        if not stat then
          log.warn("The dir does not exist: " .. source)
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
    self:query_path_detail(self.cwd, basename)
  end

  self.yank_list = {}
  self:update_buffer_render()
end

return actions
