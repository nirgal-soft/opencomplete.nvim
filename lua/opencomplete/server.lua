local config = require('opencomplete.config')
local http = require('opencomplete.http')

local M = {}

-- Server status
M.status = {
  connected = false,
  error = nil,
  providers = {},
  last_check = 0,
}

-- How often to re-check health (in seconds)
local HEALTH_CHECK_INTERVAL = 30

-- Check server health
function M.check_health(callback)
  local url = config.get_base_url() .. '/health'

  http.get(url, function(err, data)
    if err then
      M.status.connected = false
      M.status.error = err
      M.status.providers = {}
    else
      M.status.connected = true
      M.status.error = nil
      M.status.providers = data.providers or {}
    end
    M.status.last_check = os.time()

    if callback then
      callback(M.status)
    end
  end)
end

-- Check if we should re-check health
function M.maybe_check_health(callback)
  local now = os.time()
  if now - M.status.last_check > HEALTH_CHECK_INTERVAL then
    M.check_health(callback)
  elseif callback then
    callback(M.status)
  end
end

-- Get the default provider name
function M.get_default_provider()
  for _, provider in ipairs(M.status.providers) do
    if provider.is_default then
      return provider.id
    end
  end
  return nil
end

-- Check if server is available
function M.is_available()
  return M.status.connected
end

-- Get status string for statusline
function M.get_status_string()
  if not M.status.connected then
    if M.status.error then
      return ' err'
    end
    return ''
  end
  return ''
end

-- Warmup the model by sending a tiny completion request
-- This loads the model into GPU/memory so subsequent requests are fast
function M.warmup()
  if not M.status.connected then
    return
  end

  local url = config.get_base_url() .. '/complete'
  local body = {
    prefix = '//',
    suffix = '',
    language = 'rust',
    max_tokens = 1,
  }

  -- Fire and forget - we don't care about the response
  local body_json = vim.json.encode(body)
  local cmd = {
    'curl', '-s', '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-d', body_json,
    url,
  }

  vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code, _)
      if exit_code == 0 then
        require('opencomplete.log').debug('Model warmup complete')
      end
    end,
  })
end

return M
