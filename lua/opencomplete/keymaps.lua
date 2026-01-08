local config = require('opencomplete.config')
local preview = require('opencomplete.preview')

local M = {}

function M.setup()
  if config.options.disable_keymaps then
    return
  end

  local accept_key = config.options.keymaps.accept_suggestion

  if accept_key then
    vim.keymap.set('i', accept_key, function()
      if preview.has_suggestion() then
        -- Schedule the accept to run after the keymap handler returns
        vim.schedule(function()
          preview.accept()
        end)
      end
    end, {
      silent = true,
      noremap = true,
      desc = 'Accept OpenComplete suggestion',
    })
  end
end

function M.teardown()
  local accept_key = config.options.keymaps.accept_suggestion

  if accept_key then
    pcall(vim.keymap.del, 'i', accept_key)
  end
end

return M
