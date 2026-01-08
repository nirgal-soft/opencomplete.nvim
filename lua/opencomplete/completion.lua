local config = require('opencomplete.config')
local http = require('opencomplete.http')
local server = require('opencomplete.server')
local preview = require('opencomplete.preview')
local log = require('opencomplete.log')

local M = {}

-- Debounce timer
M.timer = nil

-- Whether completions are enabled
M.enabled = true

-- Track typing state for smart completion
M.insert_char_count = 0  -- Characters typed since entering insert mode
M.first_completion_done = false  -- Have we shown a completion this insert session?

-- Cancel any pending completion request
function M.cancel()
  -- Cancel debounce timer
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end

  -- Cancel HTTP request
  http.cancel()

  -- Clear preview
  preview.clear()
end

-- Build completion request from current buffer state
-- Detect whether we should do single-line or multi-line completion
-- Returns 'single_line' or 'multi_line'
local function detect_completion_mode(prefix)
  -- Get the last line of the prefix (current line up to cursor)
  local last_line = prefix:match('[^\n]*$') or ''

  -- Strip leading whitespace to see what's actually on the line
  local trimmed = last_line:match('^%s*(.*)') or ''

  -- Multi-line: empty/whitespace-only line
  if trimmed == '' then
    return 'multi_line'
  end

  -- Multi-line: block opener at end
  if trimmed:match('[{:]%s*$') then
    return 'multi_line'
  end

  -- Multi-line: comment line
  if trimmed:match('^//') or trimmed:match('^#') or trimmed:match('^%-%-') then
    return 'multi_line'
  end

  -- Multi-line: declaration keywords
  -- Rust
  if trimmed:match('^pub%s') or trimmed:match('^pub$')
    or trimmed:match('^fn%s') or trimmed:match('^fn$')
    or trimmed:match('^async%s')
    or trimmed:match('^struct%s') or trimmed:match('^struct$')
    or trimmed:match('^enum%s') or trimmed:match('^enum$')
    or trimmed:match('^impl%s') or trimmed:match('^impl$')
    or trimmed:match('^trait%s') or trimmed:match('^trait$')
    or trimmed:match('^type%s')
    or trimmed:match('^const%s')
    or trimmed:match('^static%s')
    or trimmed:match('^mod%s')
    or trimmed:match('^use%s')
    or trimmed:match('^macro_rules!')
    -- Python
    or trimmed:match('^def%s') or trimmed:match('^def$')
    or trimmed:match('^class%s') or trimmed:match('^class$')
    or trimmed:match('^async%s+def')
    -- JavaScript/TypeScript
    or trimmed:match('^function%s') or trimmed:match('^function$')
    or trimmed:match('^export%s')
    or trimmed:match('^interface%s')
    or trimmed:match('^abstract%s')
    -- Lua
    or trimmed:match('^local%s+function')
    or trimmed:match('^function%s')
  then
    return 'multi_line'
  end

  -- Otherwise, we're mid-line → single-line completion
  return 'single_line'
end

local function build_request()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]

  -- Get all lines in buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Build prefix (everything before cursor)
  local prefix_lines = {}
  for i = 1, row - 1 do
    table.insert(prefix_lines, lines[i])
  end
  -- Add current line up to cursor
  local current_line = lines[row] or ''
  table.insert(prefix_lines, current_line:sub(1, col))
  local prefix = table.concat(prefix_lines, '\n')

  -- Build suffix (everything after cursor)
  local suffix_lines = {}
  -- Rest of current line after cursor
  table.insert(suffix_lines, current_line:sub(col + 1))
  -- Remaining lines
  for i = row + 1, #lines do
    table.insert(suffix_lines, lines[i])
  end
  local suffix = table.concat(suffix_lines, '\n')

  -- Get language/filetype
  local language = vim.bo[buf].filetype
  if language == '' then
    language = 'text'
  end

  -- Get file path
  local file_path = vim.fn.expand('%:p')
  if file_path == '' then
    file_path = nil
  end

  -- Get style hints for this filetype
  local style_hints = config.get_style_hints(language)

  -- Detect single-line vs multi-line completion mode
  local mode = detect_completion_mode(prefix)
  local max_tokens = config.options.completion.max_tokens
  local stop = {}

  if mode == 'single_line' then
    -- Limit tokens and stop at newline for mid-line completions
    max_tokens = math.min(max_tokens, 64)
    stop = { '\n' }
    log.debug('Completion mode: single_line (max_tokens=%d)', max_tokens)
  else
    log.debug('Completion mode: multi_line (max_tokens=%d)', max_tokens)
  end

  return {
    prefix = prefix,
    suffix = suffix,
    language = language,
    file_path = file_path,
    max_tokens = max_tokens,
    stop = stop,
    provider = config.options.completion.provider,
    style_hints = style_hints,
  }
end

-- Check if the user just typed a character that matches the start of the current suggestion
-- If so, advance the suggestion instead of making a new request
local function check_typing_matches_suggestion()
  if not preview.has_suggestion() then
    return false
  end

  local display_text = preview.state.display_text
  if not display_text or display_text == '' then
    return false
  end

  -- Get what was just typed (character before cursor)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]

  if col == 0 then
    return false
  end

  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
  local typed_char = line:sub(col, col)

  -- Check if the typed character matches the first character of the suggestion
  local first_char = display_text:sub(1, 1)

  if typed_char == first_char then
    -- Advance the suggestion by removing the first character
    local remaining = display_text:sub(2)
    if remaining == '' then
      -- User completed the entire suggestion by typing
      preview.clear()
      log.debug('Trigger: user typed entire suggestion')
    else
      -- Update the suggestion with remaining text
      -- We need to re-render at the new cursor position
      log.debug('Trigger: advancing suggestion, remaining: %d chars', #remaining)
      preview.render_raw(remaining)
    end
    return true
  end

  return false
end

-- Trigger a completion request (with debounce)
function M.trigger()
  -- Increment character count
  M.insert_char_count = M.insert_char_count + 1

  -- Check if user is typing what's already in the suggestion
  if check_typing_matches_suggestion() then
    log.debug('Trigger: typed char matches suggestion, skipping request')
    return
  end

  -- Cancel any existing request (but not immediately if we have a suggestion)
  M.cancel()

  -- Check if completions are enabled
  if not M.enabled then
    log.debug('Trigger: completions disabled')
    return
  end

  -- Check if we should complete (filetype, condition)
  if not config.should_complete() then
    log.debug('Trigger: should_complete() returned false')
    return
  end

  -- Check if server is available
  if not server.is_available() then
    log.debug('Trigger: server not available')
    -- Try to check health in case it came back up
    server.maybe_check_health()
    return
  end

  -- Check we're in insert mode
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= 'i' and mode ~= 'ic' then
    log.debug('Trigger: not in insert mode (%s)', mode)
    return
  end

  -- Use faster debounce for first completion after entering insert mode
  local debounce_ms = config.options.completion.debounce_ms
  if not M.first_completion_done and M.insert_char_count >= 1 then
    -- First completion: use very short debounce for near-instant response
    debounce_ms = 10
    log.debug('Trigger: first completion, using aggressive debounce (%dms)', debounce_ms)
  else
    log.debug('Trigger: starting debounce timer (%dms)', debounce_ms)
  end

  -- Store current buffer for validation after debounce
  local buf = vim.api.nvim_get_current_buf()

  -- Start debounce timer
  M.timer = vim.fn.timer_start(debounce_ms, function()
    M.timer = nil

    -- Validate we're still in the same context
    if vim.api.nvim_get_current_buf() ~= buf then
      return
    end

    local current_mode = vim.api.nvim_get_mode().mode
    if current_mode ~= 'i' and current_mode ~= 'ic' then
      return
    end

    -- Build and send request
    M.request()
    M.first_completion_done = true
  end)
end

-- Send completion request immediately (no debounce)
function M.request()
  log.debug('Request: starting')

  -- Check if server is available
  if not server.is_available() then
    log.debug('Request: server not available')
    return
  end

  local request = build_request()
  local url = config.get_base_url() .. '/complete'

  log.debug('Request: url=%s, language=%s, prefix_len=%d, suffix_len=%d',
    url, request.language, #request.prefix, #request.suffix)

  -- Store cursor position for validation
  local start_cursor = vim.api.nvim_win_get_cursor(0)
  local start_buf = vim.api.nvim_get_current_buf()

  http.stream_completion(url, request, {
    on_chunk = function(text, _chunk)
      log.debug('on_chunk: received %d chars', text and #text or 0)

      -- Validate cursor hasn't moved
      if vim.api.nvim_get_current_buf() ~= start_buf then
        log.debug('on_chunk: buffer changed, cancelling')
        http.cancel()
        return
      end

      local current_cursor = vim.api.nvim_win_get_cursor(0)
      if current_cursor[1] ~= start_cursor[1] or current_cursor[2] ~= start_cursor[2] then
        log.debug('on_chunk: cursor moved, cancelling')
        http.cancel()
        preview.clear()
        return
      end

      -- Update preview with accumulated text
      preview.render(text)
    end,

    on_done = function(text, _finish_reason)
      log.debug('on_done: %d chars, reason=%s', text and #text or 0, _finish_reason or 'nil')
      -- Final render
      if text and text ~= '' then
        preview.render(text)
      end
    end,

    on_error = function(err)
      log.error('Completion error: %s', err)
      preview.clear()
      -- Update server status on error
      if err:match('connection') or err:match('refused') then
        server.status.connected = false
        server.status.error = err
      end
    end,
  })
end

-- Check if a request is in progress
function M.is_busy()
  return http.is_busy() or M.timer ~= nil
end

-- Enable completions
function M.enable()
  M.enabled = true
end

-- Disable completions
function M.disable()
  M.enabled = false
  M.cancel()
end

-- Toggle completions
function M.toggle()
  if M.enabled then
    M.disable()
  else
    M.enable()
  end
end

-- Reset insert mode state (called on InsertEnter/InsertLeave)
function M.reset_insert_state()
  M.insert_char_count = 0
  M.first_completion_done = false
end

return M
