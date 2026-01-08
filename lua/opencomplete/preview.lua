local M = {}

-- Namespace for extmarks
M.ns_id = vim.api.nvim_create_namespace('opencomplete')

-- Current suggestion state
M.state = {
  buffer = nil,
  row = nil,
  col = nil,
  text = nil,
  display_text = nil,  -- text with space prepended if needed
  extmark_id = nil,
}

-- Check if we need a space between prefix and completion
local function needs_space_before(buf, row, col, completion_text)
  -- If completion already starts with space/punctuation/underscore, no need
  -- Underscore is used to continue identifiers (e.g., "count" + "_chars")
  if completion_text:match('^%s') or completion_text:match('^[%p]') or completion_text:match('^_') then
    return false
  end

  -- Get character before cursor
  if col == 0 then
    return false  -- At start of line
  end

  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  local char_before = line:sub(col, col)

  -- If char before cursor is a word character and completion starts with word char (not underscore), need space
  if char_before:match('[%w_]') and completion_text:match('^[%w]') then
    return true
  end

  return false
end

-- Render ghost text at the current cursor position
function M.render(text)
  if not text or text == '' then
    return
  end

  -- Clear any existing suggestion
  M.clear()

  -- Only render in insert mode
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= 'i' and mode ~= 'ic' then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1  -- 0-indexed
  local col = cursor[2]

  -- Use text as-is - let the model/server handle spacing
  local display_text = text

  -- Split text into lines
  local lines = vim.split(display_text, '\n', { plain = true })
  local first_line = lines[1] or ''

  -- Build extmark options
  local opts = {
    hl_mode = 'combine',
    priority = 1000,
    virt_text = {{ first_line, 'OpenCompleteGhost' }},
    virt_text_pos = 'inline',
  }

  -- Add virtual lines for multi-line completions
  if #lines > 1 then
    local virt_lines = {}
    for i = 2, #lines do
      table.insert(virt_lines, {{ lines[i], 'OpenCompleteGhost' }})
    end
    opts.virt_lines = virt_lines
  end

  -- Create extmark
  local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_id, row, col, opts)
  if ok then
    M.state = {
      buffer = buf,
      row = row,
      col = col,
      text = text,
      display_text = display_text,
      extmark_id = extmark_id,
    }
  end
end

-- Clear the current suggestion
function M.clear()
  if M.state.buffer and vim.api.nvim_buf_is_valid(M.state.buffer) then
    vim.api.nvim_buf_clear_namespace(M.state.buffer, M.ns_id, 0, -1)
  end
  M.state = {
    buffer = nil,
    row = nil,
    col = nil,
    text = nil,
    display_text = nil,
    extmark_id = nil,
  }
end

-- Check if there's an active suggestion
function M.has_suggestion()
  return M.state.text ~= nil and M.state.text ~= ''
end

-- Get the current suggestion text
function M.get_text()
  return M.state.text
end

-- Render ghost text without recalculating space (used when advancing suggestion)
function M.render_raw(text)
  if not text or text == '' then
    M.clear()
    return
  end

  -- Clear any existing suggestion
  local old_buffer = M.state.buffer
  if old_buffer and vim.api.nvim_buf_is_valid(old_buffer) then
    vim.api.nvim_buf_clear_namespace(old_buffer, M.ns_id, 0, -1)
  end

  -- Only render in insert mode
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= 'i' and mode ~= 'ic' then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1  -- 0-indexed
  local col = cursor[2]

  -- Split text into lines
  local lines = vim.split(text, '\n', { plain = true })
  local first_line = lines[1] or ''

  -- Build extmark options
  local opts = {
    hl_mode = 'combine',
    priority = 1000,
    virt_text = {{ first_line, 'OpenCompleteGhost' }},
    virt_text_pos = 'inline',
  }

  -- Add virtual lines for multi-line completions
  if #lines > 1 then
    local virt_lines = {}
    for i = 2, #lines do
      table.insert(virt_lines, {{ lines[i], 'OpenCompleteGhost' }})
    end
    opts.virt_lines = virt_lines
  end

  -- Create extmark
  local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns_id, row, col, opts)
  if ok then
    M.state = {
      buffer = buf,
      row = row,
      col = col,
      text = text,
      display_text = text,  -- Already processed, no space needed
      extmark_id = extmark_id,
    }
  end
end

-- Accept the current suggestion (insert text at cursor)
function M.accept()
  if not M.has_suggestion() then
    return false
  end

  -- Use the display_text which already has space prepended if needed
  local text = M.state.display_text
  local buf = M.state.buffer
  local row = M.state.row  -- 0-indexed
  local col = M.state.col

  -- Clear the preview first
  M.clear()

  -- Split text into lines for nvim_buf_set_text
  local lines = vim.split(text, '\n', { plain = true })

  -- Insert text at the stored cursor position
  -- nvim_buf_set_text(buf, start_row, start_col, end_row, end_col, replacement)
  vim.api.nvim_buf_set_text(buf, row, col, row, col, lines)

  -- Move cursor to end of inserted text
  local new_row = row + #lines - 1
  local new_col
  if #lines == 1 then
    new_col = col + #lines[1]
  else
    new_col = #lines[#lines]
  end
  vim.api.nvim_win_set_cursor(0, { new_row + 1, new_col })

  return true
end

-- Check if cursor has moved away from the suggestion
function M.is_cursor_at_suggestion()
  if not M.state.buffer then
    return false
  end

  local buf = vim.api.nvim_get_current_buf()
  if buf ~= M.state.buffer then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  return row == M.state.row and col == M.state.col
end

return M
