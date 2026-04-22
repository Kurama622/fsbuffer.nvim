local log = {}
function log.error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "Fsbuffer" })
end
function log.warn(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = "Fsbuffer" })
end
return log
