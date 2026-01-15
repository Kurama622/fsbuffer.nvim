local keymaps = {}
local actions = require("fsbuffer.action")

local return_normal = function()
  local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
end

local replace = function(new_char)
  local start_row, end_row = actions:range()

  -- 获取选区覆盖的视觉列（Virtual Columns）
  -- 使用 curswant 处理 Ctrl-v 的矩形边界
  local left_vcol = vim.fn.virtcol("'<")
  local right_vcol = vim.fn.virtcol("'>")

  -- 确保左小右大
  if left_vcol > right_vcol then
    left_vcol, right_vcol = right_vcol, left_vcol
  end

  -- 3. 遍历每一行进行精准替换
  for lnum = start_row, end_row do
    -- 将视觉列转换为该行具体的字节位置
    -- vim.fn.virtcol2col 能处理 inline 虚拟文本带来的偏移
    local byte_start = vim.fn.virtcol2col(0, lnum, left_vcol)
    local byte_end = vim.fn.virtcol2col(0, lnum, right_vcol)

    if byte_start > 0 then
      -- 替换该行指定范围内的字符
      -- nvim_buf_set_text 的坐标是从 0 开始的，且不包含终点
      vim.api.nvim_buf_set_text(0, lnum - 1, byte_start - 1, lnum - 1, byte_end, { new_char })
    end
  end
  return_normal()
  return start_row, end_row
end

function keymaps:setup()
  local t = {
    -- visual block
    {
      action = function()
        self.mode = "\22"
        return "<C-v>"
      end,
      mode = "n",
      key = "<C-v>",
      opts = { noremap = true, buffer = true, expr = true },
    },

    -- visual
    {
      action = function()
        self.mode = "v"
        return "v"
      end,
      mode = "n",
      key = "v",
      opts = { noremap = true, buffer = true, expr = true },
    },

    -- visual line
    {
      action = function()
        self.mode = "V"
        return "V"
      end,
      mode = "n",
      key = "V",
      opts = { noremap = true, buffer = true, expr = true },
    },

    -- move down
    {
      action = function()
        local row = vim.api.nvim_win_get_cursor(0)[1]
        if row == (1 + #self.lines) then
          vim.schedule(function()
            pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
          end)
          return ""
        else
          return "j"
        end
      end,
      mode = "n",
      key = "j",
      opts = { noremap = true, buffer = true, expr = true },
    },

    -- move up
    {
      action = function()
        local row = vim.api.nvim_win_get_cursor(0)[1]
        if row == 2 then
          vim.schedule(function()
            pcall(vim.api.nvim_win_set_cursor, 0, { #self.lines + 1, 0 })
          end)
          return ""
        end
        return "k"
      end,
      mode = "n",
      key = "k",
      opts = { noremap = true, buffer = true, expr = true },
    },

    -- enter parent dir
    {
      action = function()
        self:update_buffer_render(vim.fs.dirname(self.cwd))
      end,
      mode = "n",
      key = self.cfg.keymap.enter_parent_dir,
      opts = { noremap = true, buffer = true },
    },

    -- replace
    {
      action = function()
        local old_cursor = vim.opt.guicursor:get()
        vim.opt.guicursor:append("a:hor20-blinkon200")
        local char_code = vim.fn.getchar()
        vim.opt.guicursor = old_cursor
        local char = type(char_code) == "number" and vim.fn.nr2char(char_code) or char_code

        self.mode = "r"
        if char_code == 27 then
          return_normal()
          return
        end
        local start_row, end_row = replace(char)

        local texts = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, true)

        for i, text in ipairs(texts) do
          actions:rename(start_row + i - 2, self.cwd, self.lines[start_row + i - 2].name, (text:gsub("%s+$", "")))
        end
      end,
      mode = { "x", "n" },
      key = "r",
      opts = { noremap = true, buffer = true }
    },

    -- open
    {
      action = function()
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
      mode = "n",
      key = self.cfg.keymap.open,
      opts = { noremap = true, buffer = true },
    },

    -- search
    {
      action = function()
        self.mode = "c"
        self.action = "normal"
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.cmd("startinsert!")
      end,
      mode = "n",
      key = "/",
      opts = { noremap = true, buffer = true },
    },

    -- add
    {
      action = function()
        if self.lines_idx_map ~= nil then
          self.lines_idx_map = nil
          self:update_buffer_render()
        end
        self.action = "add"
        local row = vim.api.nvim_buf_line_count(self.buf)
        vim.api.nvim_buf_set_lines(self.buf, row, row, true, { "" })
        vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
        vim.cmd.startinsert()
      end,
      mode = "n",
      key = "o",
      opts = { noremap = true, buffer = true },
    },

    -- cut
    {
      action = function()
        local mode = vim.api.nvim_get_mode().mode
        if mode == "no" or mode == "V" then
          self.action = "cut"

          local start_row, end_row = actions:range()
          for i = start_row, end_row, 1 do
            table.insert(
              self.cut_list,
              { path = self.cwd, name = self.lines[i - 1].name, ["type"] = self.lines[i - 1].type, idx = i - 1 }
            )
            self.lines[i - 1].dired = true
          end
          vim.schedule(function()
            return_normal()
            self:update_buffer_render()
          end)
        elseif mode == "\22" or mode == "v" then
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
            return_normal()
          end)
        end
      end,
      mode = { "x", "o" },
      key = "d",
      opts = { noremap = true, buffer = true },
    },

    -- yank
    {
      action = function()
        self.action = "yank"
        local start_row, end_row = actions:range()
        for i = start_row, end_row, 1 do
          table.insert(
            self.yank_list,
            { path = self.cwd, name = self.lines[i - 1].name, ["type"] = self.lines[i - 1].type }
          )
        end
        return "y"
      end,
      mode = { "x", "n" },
      key = "y",
      opts = { noremap = true, buffer = true, expr = true },
    },

    -- paste
    {
      action = function()
        self.action = "paste"
        vim.schedule(function()
          actions:rename_all(self.cut_list)
          actions:paste_all(self.yank_list)
        end)
        return "p"
      end,
      mode = { "x", "n" },
      key = "p",
      opts = { noremap = true, buffer = true, expr = true },
    },
  }

  for _, map in ipairs(t) do
    vim.keymap.set(map.mode, map.key, map.action, map.opts)
  end
end

return keymaps
