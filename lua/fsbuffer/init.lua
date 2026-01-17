local fsb = {
  exist = false,
  lines = {},
  cwd = nil,
  lines_idx_map = nil,
  max_name_width = 0,
  max_user_width = 0,
  max_date_width = 0,
  last_cursor_row = 1,
  search_job = nil,
  search_id = 0,
  cut_list = {},
  yank_list = {},
  mode = "n",
  action = "normal",
  edit = { range = { start_row = nil, end_row = nil, start_col = nil, end_col = nil }, texts = {}, modified = false },
  buf = nil,
  win = nil,
}

local actions, keymaps = require("fsbuffer.action"), require("fsbuffer.keymaps")

for _, t in ipairs({ actions, keymaps }) do
  setmetatable(t, {
    __index = fsb,

    __newindex = function(_, key, value)
      fsb[key] = value
    end,
  })
end

local ns_id = vim.api.nvim_create_namespace("fsbuffer_highlights")
local fsb_group = vim.api.nvim_create_augroup("FsBuffer", { clear = true })

function fsb:set_window_max_width()
  self.cfg.width = math.min(
    self.cfg.max_window_width,
    math.max(
      vim.api.nvim_strwidth(self.cwd) - vim.api.nvim_strwidth(vim.env.HOME) + 2,
      self.max_name_width + self.max_user_width + self.max_date_width + 33
    )
  )
end

local function parse_fd_output(line, current_path)
  if #line == 0 then
    return nil
  end

  local entry = {}
  local data = vim
    .iter(vim.split(line, "%s"))
    :map(function(item)
      if #item > 0 then
        return item
      end
    end)
    :totable()
  if #data < 9 then
    return
  end
  entry.mode = data[1]:gsub("@$", "")
  entry.type = entry.mode:sub(1, 1) == "d" and "directory" or "file"
  local name = data[9]:sub(#current_path + 1)
  entry.name = entry.type == "directory" and name .. "/" or name
  return entry
end

function fsb:search_with_cmd_fd(search_words, path)
  local search_cmd = {
    "fd",
    "-l",
    "-i",
    "-H",
    "--max-depth",
    tostring(self.cfg.search.max_depth),
    "--color",
    "never",
    search_words,
    path,
  }
  if not vim.tbl_isempty(self.cfg.search.ignore) then
    for _, ignore in ipairs(self.cfg.search.ignore) do
      table.insert(search_cmd, "--exclude")
      table.insert(search_cmd, ignore)
    end
  end

  local id = self.search_id
  self.lines = {}
  return vim.system(search_cmd, {
    text = true,
    stdout = function(_, data)
      if self.search_id ~= id then
        return
      end
      if data then
        local lines = {}
        for _, line in ipairs(vim.split(data, "\n")) do
          if #line > 0 then
            local entry = parse_fd_output(line, path)
            table.insert(lines, entry)
          end
        end

        if not vim.tbl_isempty(lines) then
          vim.schedule(function()
            self:merge_and_sort_search_res(search_words, lines, id)
          end)
        end
      end
    end,
  }, function()
    if self.search_id ~= id then
      return
    end
    self.search_job = nil
    vim.schedule(function()
      self:update_search_render()
    end)
  end)
end

function fsb:search_with_cmd_none(search_words)
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

function fsb.setup(opts)
  fsb.cfg = vim.tbl_deep_extend("force", require("fsbuffer.config"), opts)
end

function fsb:init_window_config()
  self.cfg.height = self.cfg.height or math.floor(vim.o.lines * self.cfg.height_ratio)
  self:set_window_max_width()
  self.cfg.row = self.cfg.row or math.floor((vim.o.lines - self.cfg.height) / 2)
  self.cfg.col = self.cfg.col or math.floor((vim.o.columns - self.cfg.width) / 2)
end

function fsb:update_window()
  if self.win then
    self:set_window_max_width()
    self.cfg.col = math.floor((vim.o.columns - self.cfg.width) / 2)
    vim.api.nvim_win_set_config(self.win, {
      relative = self.cfg.relative,
      border = self.cfg.border,
      row = self.cfg.row,
      col = self.cfg.col,
      height = self.cfg.height,
      width = self.cfg.width,
    })
    if self.mode ~= "c" then
      pcall(vim.api.nvim_win_set_cursor, self.win, { self.last_cursor_row, 0 })
      self.last_cursor_row = 1
    end
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
  self.yank_list, self.cut_list = {}, {}
  self.last_cursor_row = 1
  self.search_id = 0
  self.mode = "n"
  self.action = "normal"
end

function fsb:create_fs_buffer(dir)
  self.buf = vim.api.nvim_create_buf(false, true)
  dir = dir or vim.uv.cwd() .. "/"

  vim.api.nvim_buf_create_user_command(self.buf, "FsEdit", function()
    self.last_cursor_row = vim.api.nvim_win_get_cursor(0)[1]
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

  vim.api.nvim_buf_create_user_command(self.buf, "FsRename", function()
    if not vim.tbl_isempty(self.edit.texts) then
      if not self.edit.modified then
        self:update_buffer_render()
      else
        vim.schedule(function()
          local new_texts =
            vim.api.nvim_buf_get_lines(self.buf, self.edit.range.start_row - 1, self.edit.range.end_row, true)

          for i, raw_text in ipairs(self.edit.texts) do
            actions:rename(
              self.edit.range.start_row + i - 2,
              self.cwd,
              (raw_text:gsub("%s+$", "")),
              (new_texts[i]:gsub("%s+$", ""))
            )
          end
          self.edit = {
            range = { start_row = nil, end_row = nil, start_col = nil, end_col = nil },
            texts = {},
            modified = false,
          }
        end)
      end
    end
  end, {})

  if self.cfg == nil then
    self.cfg = require("fsbuffer.config")
  end
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

  vim.wo[self.win].wrap = false
  vim.wo[self.win].winfixbuf = true
  vim.wo[self.win].number = false
  vim.wo[self.win].relativenumber = false
  vim.wo[self.win].signcolumn = "no"
  vim.wo[self.win].spell = false
  vim.bo[self.buf].filetype = "fsbuffer"
  vim.bo[self.buf].buftype = "acwrite"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  vim.bo[self.buf].undolevels = -1
  vim.b[self.buf].completion = self.cfg.enable_completion

  vim.api.nvim_buf_set_name(self.buf, "fsbuffer")
  vim.cmd.syntax('match FsDir "[^[:space:]]\\+/"')
  keymaps:setup()

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

  self:event_watch()

  self.exist = true
end

function fsb:update_root_dir_hightlight(path)
  vim.api.nvim_buf_set_extmark(self.buf, ns_id, 0, 0, {
    end_col = #path,
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
    return false
  end

  while true do
    local name, _ = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    actions:query_path_detail(cwd, name)
  end
  return true
end

function fsb:merge_and_sort_search_res(search_words, lines, id)
  if self.search_id ~= id then
    return
  end
  local res = vim.fn.matchfuzzypos(
    vim
      .iter(lines)
      :map(function(entry)
        return entry.name
      end)
      :totable(),
    search_words
  )

  -- exclude: the paths containing the search words
  local filters = {}
  for _, entry in ipairs(lines) do
    for k, v in ipairs(res[1]) do
      if v == entry.name then
        entry.match_pos = res[2][k]
        entry.score = res[3][k] or 0

        table.insert(filters, entry)
      end
    end
  end

  self.lines = vim.list_extend(self.lines, filters)

  table.sort(self.lines, function(a, b)
    return a.score > b.score
  end)
end

function fsb:update_search_render()
  -- clear buf text and extmarks
  vim.api.nvim_buf_set_lines(self.buf, 1, -1, false, {})
  local extmarks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, 0, -1, {})
  for _, mark in ipairs(extmarks) do
    vim.api.nvim_buf_del_extmark(self.buf, ns_id, mark[1])
  end
  self:update_root_dir_hightlight(self.cwd:gsub(vim.env.HOME, "~"))

  vim.api.nvim_buf_set_extmark(self.buf, ns_id, 0, 0, {
    virt_lines = {
      { { " " .. string.rep("─", self.cfg.width - 2) .. " ", "Comment" } },
    },
    virt_lines_above = false,
  })

  for row, line in ipairs(self.lines) do
    vim.api.nvim_buf_set_lines(self.buf, row, row, false, { line.name })
    vim.api.nvim_buf_set_extmark(self.buf, ns_id, row, 0, {
      virt_text = { { " ", "FsTitle" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })

    if line.match_pos then
      for _, col in ipairs(line.match_pos) do
        vim.api.nvim_buf_set_extmark(self.buf, ns_id, row, col, {
          end_col = col + 1,
          hl_group = "FsMatch",
          hl_mode = "combine",
        })
      end
    end
  end
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
    if self:scan(root_dir) then
      self.cwd = root_dir:gsub("/+$", "")
    end
  end

  -- render current path
  --- @type string
  local path = self.cwd
  if vim.startswith(path, vim.env.HOME) then
    path = root_dir == self.cwd and "~" .. path:sub(#vim.env.HOME + 1) or "~" .. path:sub(#vim.env.HOME + 1) .. "/"
  end
  if not keep_title then
    vim.api.nvim_buf_set_lines(self.buf, 0, 1, false, { path })
  end
  self:update_root_dir_hightlight(path)

  self:set_window_max_width()
  vim.api.nvim_buf_set_extmark(self.buf, ns_id, 0, 0, {
    virt_lines = {
      { { " " .. string.rep("─", self.cfg.width - 2) .. " ", "Comment" } },
    },
    virt_lines_above = false,
  })

  lines = lines or self.lines
  for row, line in ipairs(lines) do
    local display_width = vim.fn.strdisplaywidth(line.name)
    local padding_count = (self.max_name_width + 2) - display_width
    local padded_text = line.name .. string.rep(" ", math.max(0, padding_count))
    vim.api.nvim_buf_set_lines(self.buf, row, row, false, { padded_text })

    local status = (
      line.dired
      or (
        self.cut_list
        and not vim.tbl_isempty(vim.tbl_filter(function(item)
          return item.path == self.cwd and item.name == line.name
        end, self.cut_list))
      )
    )
        and " " .. self.cfg.indicator
      or string.rep(" ", vim.fn.strdisplaywidth(self.cfg.indicator) + 1)
    lines[row].dired_id = vim.api.nvim_buf_set_extmark(self.buf, ns_id, row, 0, {
      virt_text = { { status, "FsTitle" } },
      virt_text_pos = "inline",
      right_gravity = false,
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

  self:update_window()
end

function fsb:event_watch()
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = fsb_group,
    buffer = self.buf,
    callback = function()
      -- search mode
      if self.mode == "c" and self.do_search == true then
        -- clear idx map
        self.lines_idx_map = nil

        ---@type string
        local path = self.cwd
        if vim.startswith(path, vim.env.HOME) then
          path = "~" .. path:sub(#vim.env.HOME + 1) .. "/"
        end
        local text = vim.api.nvim_buf_get_lines(self.buf, 0, 1, true)[1]

        local search_path = (text:gsub("~", vim.env.HOME))
        local stat = vim.uv.fs_stat(search_path)
        local stat_type = stat and stat.type or nil
        local is_dir_search = search_path:sub(-1) == "/"
        if is_dir_search and stat_type == "directory" then
          self.search_id = self.search_id + 1
          self:update_buffer_render(search_path)
        elseif #text >= #path then
          local search_words = text:gsub(path, "")
          if self.cfg.search.cmd == "none" then
            self:search_with_cmd_none(search_words)
          elseif self.cfg.search.cmd == "fd" then
            if self.search_job then
              self.search_job:kill(9)
            end
            self.search_id = self.search_id + 1
            self.search_job = self:search_with_cmd_fd(search_words, (path:gsub("~", vim.env.HOME)))
          end
        end
      elseif not vim.tbl_isempty(self.edit.texts) then
        self.edit.modified = true
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = fsb_group,
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
    group = fsb_group,
    buffer = self.buf,
    callback = function()
      -- 首行插入为搜索
      if vim.api.nvim_win_get_cursor(0)[1] == 1 then
        self.mode = "c"
      end

      if self.mode == "c" then
        return
      end

      -- visual block需要特殊处理
      self.mode = self.mode == "\22" and "\22" or "i"
      vim.cmd.FsEdit()
    end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = fsb_group,
    buffer = self.buf,
    callback = function()
      if self.mode == "c" then
        self.mode = "n"
        -- update root dir
        --- @type string
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

      vim.cmd.FsRename()
      self.mode = "n"

      -- create
      if self.action == "add" then
        -- self.last_cursor_row = vim.api.nvim_win_get_cursor(0)[1]
        actions:create_and_render()
      end
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineChanged", {
    group = fsb_group,
    buffer = self.buf,
    callback = function()
      local cmd = vim.fn.getcmdline()
      if cmd:match("^%%s/") then
        local new_cmd = "2,$" .. cmd:sub(2)
        vim.fn.setcmdline(new_cmd)
        local pos = vim.fn.getcmdpos()
        vim.fn.setcmdpos(pos + 2)
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = fsb_group,
    buffer = self.buf,
    callback = function()
      self:close()
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = fsb_group,
    buffer = self.buf,
    callback = function()
      self.last_cursor_row = vim.api.nvim_buf_line_count(self.buf) - #self.cut_list
      actions:remove_all(self.cut_list)
      vim.bo[self.buf].modified = false
    end,
  })

  vim.api.nvim_create_autocmd("QuitPre", {
    group = fsb_group,
    buffer = self.buf,
    callback = function()
      if self.cfg.delete_the_cut_on_close then
        actions:remove_all(self.cut_list)
      end
      vim.bo[self.buf].modified = false
    end,
  })
end

return fsb
