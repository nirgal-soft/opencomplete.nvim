local log = require('opencomplete.log')

local M = {}

-- Active request job (for cancellation)
M.active_job = nil

-- Parse SSE data line and extract JSON
local function parse_sse_line(line)
  -- Remove carriage return if present
  line = line:gsub('\r$', '')

  if line:match('^data: ') then
    local json_str = line:sub(7)
    local ok, data = pcall(vim.json.decode, json_str)
    if ok then
      return data
    else
      log.debug('Failed to parse JSON: %s', json_str)
    end
  end
  return nil
end

-- Stream a completion request using SSE via curl
-- callbacks: { on_chunk, on_done, on_error }
function M.stream_completion(url, body, callbacks)
  callbacks = callbacks or {}

  -- Cancel any existing request
  M.cancel()

  local accumulated_text = ''
  local buffer = ''
  local body_json = vim.json.encode(body)

  log.debug('POST %s', url)
  log.debug('Body: %s', body_json)

  -- Use vim.fn.jobstart for more control
  local stdout_handler = function(_, data, _)
    if not data then return end

    for _, line in ipairs(data) do
      if line and line ~= '' then
        buffer = buffer .. line .. '\n'
      end
    end

    -- Process complete lines from buffer
    while true do
      local newline_pos = buffer:find('\n')
      if not newline_pos then
        break
      end

      local line = buffer:sub(1, newline_pos - 1)
      buffer = buffer:sub(newline_pos + 1)

      -- Skip empty lines (SSE separators)
      if line ~= '' and line ~= '\r' then
        log.debug('SSE line: %s', line)
        local data_parsed = parse_sse_line(line)
        if data_parsed then
          -- Check for error response
          if data_parsed.error then
            log.error('Server error: %s', data_parsed.error)
            vim.schedule(function()
              if callbacks.on_error then
                callbacks.on_error(data_parsed.error)
              end
            end)
            M.cancel()
            return
          end

          -- Accumulate text
          if data_parsed.text then
            accumulated_text = accumulated_text .. data_parsed.text
            log.debug('Accumulated: %d chars', #accumulated_text)
            vim.schedule(function()
              if callbacks.on_chunk then
                callbacks.on_chunk(accumulated_text, data_parsed)
              end
            end)
          end

          -- Check if final chunk
          if data_parsed.is_final then
            log.debug('Final chunk received')
            vim.schedule(function()
              if callbacks.on_done then
                callbacks.on_done(accumulated_text, data_parsed.finish_reason)
              end
            end)
            M.active_job = nil
            return
          end
        end
      end
    end
  end

  local stderr_handler = function(_, data, _)
    if data and #data > 0 then
      local stderr_text = table.concat(data, '\n')
      if stderr_text ~= '' then
        log.debug('curl stderr: %s', stderr_text)
      end
    end
  end

  local exit_handler = function(_, exit_code, _)
    log.debug('curl exited with code %d', exit_code)
    M.active_job = nil

    -- 143 = killed by SIGTERM (normal cancellation)
    -- 0 = success
    if exit_code ~= 0 and exit_code ~= 143 then
      vim.schedule(function()
        if callbacks.on_error then
          callbacks.on_error('curl exited with code ' .. exit_code)
        end
      end)
    end
  end

  -- Build curl command
  local cmd = {
    'curl',
    '-s',
    '-N',  -- No buffering
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', 'Accept: text/event-stream',
    '-d', body_json,
    url,
  }

  log.debug('Running: %s', table.concat(cmd, ' '))

  M.active_job = vim.fn.jobstart(cmd, {
    on_stdout = stdout_handler,
    on_stderr = stderr_handler,
    on_exit = exit_handler,
    stdout_buffered = false,
    stderr_buffered = false,
  })

  if M.active_job <= 0 then
    log.error('Failed to start curl job: %d', M.active_job)
    M.active_job = nil
    if callbacks.on_error then
      callbacks.on_error('Failed to start curl')
    end
  else
    log.debug('curl job started: %d', M.active_job)
  end

  return M.active_job
end

-- Cancel the active request
function M.cancel()
  if M.active_job and M.active_job > 0 then
    log.debug('Cancelling job %d', M.active_job)
    vim.fn.jobstop(M.active_job)
    M.active_job = nil
  end
end

-- Check if a request is in progress
function M.is_busy()
  return M.active_job ~= nil and M.active_job > 0
end

-- Simple GET request for health check
function M.get(url, callback)
  local cmd = { 'curl', '-s', url }

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if data then
        local body = table.concat(data, '')
        if body ~= '' then
          local ok, parsed = pcall(vim.json.decode, body)
          vim.schedule(function()
            if ok then
              callback(nil, parsed)
            else
              callback('Failed to parse response: ' .. body)
            end
          end)
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        vim.schedule(function()
          callback('curl exited with code ' .. exit_code)
        end)
      end
    end,
    stdout_buffered = true,
  })
end

return M
