local completion = require('opencomplete.completion')
local preview = require('opencomplete.preview')

local M = {}

M.augroup = nil

function M.setup()
  M.augroup = vim.api.nvim_create_augroup('opencomplete', { clear = true })

  -- Reset state when entering insert mode
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = M.augroup,
    callback = function()
      completion.reset_insert_state()
    end,
  })

  -- Trigger completion on text change in insert mode
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChangedP' }, {
    group = M.augroup,
    callback = function()
      completion.trigger()
    end,
  })

  -- Clear suggestion when cursor moves (if it moved away from suggestion position)
  vim.api.nvim_create_autocmd('CursorMovedI', {
    group = M.augroup,
    callback = function()
      if preview.has_suggestion() and not preview.is_cursor_at_suggestion() then
        preview.clear()
      end
    end,
  })

  -- Clear suggestion when leaving insert mode
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = M.augroup,
    callback = function()
      completion.cancel()
      completion.reset_insert_state()
    end,
  })

  -- Clear suggestion when leaving buffer
  vim.api.nvim_create_autocmd('BufLeave', {
    group = M.augroup,
    callback = function()
      preview.clear()
    end,
  })

  -- Clear suggestion on mode change
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = M.augroup,
    pattern = 'i:*',
    callback = function()
      completion.cancel()
    end,
  })
end

function M.teardown()
  if M.augroup then
    vim.api.nvim_del_augroup_by_id(M.augroup)
    M.augroup = nil
  end
end

return M
