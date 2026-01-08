local M = {}

M.level = 'info'  -- 'debug', 'info', 'warn', 'error', 'off'

local levels = {
  debug = 1,
  info = 2,
  warn = 3,
  error = 4,
  off = 5,
}

local function should_log(level)
  return levels[level] >= levels[M.level]
end

local function log(level, msg, ...)
  if not should_log(level) then
    return
  end

  local formatted = string.format(msg, ...)
  local prefix = string.format('[opencomplete:%s]', level)

  if level == 'error' then
    vim.notify(prefix .. ' ' .. formatted, vim.log.levels.ERROR)
  elseif level == 'warn' then
    vim.notify(prefix .. ' ' .. formatted, vim.log.levels.WARN)
  elseif level == 'info' then
    vim.notify(prefix .. ' ' .. formatted, vim.log.levels.INFO)
  else
    vim.notify(prefix .. ' ' .. formatted, vim.log.levels.DEBUG)
  end
end

function M.debug(msg, ...)
  log('debug', msg, ...)
end

function M.info(msg, ...)
  log('info', msg, ...)
end

function M.warn(msg, ...)
  log('warn', msg, ...)
end

function M.error(msg, ...)
  log('error', msg, ...)
end

return M
