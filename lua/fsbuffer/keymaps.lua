local keymaps = {}
local actions = require("fsbuffer.action")

local return_normal = function()
  local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
  keymaps.mode = "n"
end

local replace = function(new_char)
  local start_row, end_row, start_col, end_col = actions:range()

  for lnum = start_row, end_row, 1 do
    vim.api.nvim_buf_set_text(0, lnum - 1, start_col - 1, lnum - 1, end_col, { new_char })
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
        self:update_buffer_render(vim.fs.dirname(self.cwd) .. "/")
        -- 路径变化则清空搜索状态
        self.lines_idx_map = nil
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
        self.last_cursor_row = start_row

        local texts = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, true)

        for i, text in ipairs(texts) do
          actions:rename(start_row + i - 2, self.cwd, self.lines[start_row + i - 2].name, (text:gsub("%s+$", "")))
        end
      end,
      mode = { "x", "n" },
      key = "r",
      opts = { noremap = true, buffer = true },
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
          self:update_buffer_render(self.cwd .. "/" .. self.lines[idx].name)
        elseif self.lines[idx].type == "file" then
          self:close()
          vim.cmd.edit(self.cwd .. "/" .. self.lines[idx].name)
          self.cwd = nil
          self.lines = {}
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
        vim.api.nvim_buf_attach(self.buf, false, {
          on_lines = function(_, _, _, firstline, lastline, _)
            if self.mode == "c" then
              if firstline == 0 then
                self.do_search = true
              else
                self.do_search = false
              end
            else
              self.do_search = false
              return true
            end
          end,
        })
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

    -- delete
    {
      action = function()
        if vim.api.nvim_get_mode().mode == "n" then
          vim.api.nvim_feedkeys("vd", "m", true)
        elseif vim.api.nvim_get_mode().mode == "\22" then
          vim.api.nvim_feedkeys("d", "m", true)
        end
      end,
      mode = { "x", "n" },
      key = "x",
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

          self.last_cursor_row = start_row
          vim.schedule(function()
            return_normal()
            self:update_buffer_render()
          end)
        elseif mode == "\22" or mode == "v" then
          vim.schedule(function()
            vim.cmd.FsEdit()
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
            vim.cmd.FsRename()
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

    -- substitute
    {
      action = function()
        self.mode = "substitute"

        self.last_cursor_row = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_attach(0, false, {
          on_lines = function(_, _, _, firstline, lastline, new_lastline)
            for i = firstline, new_lastline - 1 do
              local new_text = (vim.api.nvim_buf_get_lines(0, i, i + 1, true)[1]:gsub("%s+$", ""))
              if new_text ~= self.lines[i].name then
                table.insert(
                  self.cut_list,
                  { path = self.cwd, name = self.lines[i].name, ["type"] = self.lines[i].type }
                )
                actions:rename(i, self.cwd, self.lines[i].name, new_text)
              end
            end
            vim.cmd("nohl")
            return true
          end,
        })
        vim.api.nvim_feedkeys(":", "n", false)
      end,
      mode = { "x", "n" },
      key = ":",
      opts = { noremap = true, buffer = true },
    },

    -- others
    {
      action = function()
        return "<esc>"
      end,
      mode = "i",
      key = "<C-j>",
      opts = { noremap = true, buffer = true, expr = true },
    },
  }

  for _, map in ipairs(t) do
    vim.keymap.set(map.mode, map.key, map.action, map.opts)
  end
end

return keymaps
