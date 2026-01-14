local log = {}
function log.error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "fsbuffer" })
end
function log.warn(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = "fsbuffer" })
end
return log
