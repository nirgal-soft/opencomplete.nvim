local M = {}

local config = require('opencomplete.config')
local server = require('opencomplete.server')
local completion = require('opencomplete.completion')
local preview = require('opencomplete.preview')
local events = require('opencomplete.events')
local keymaps = require('opencomplete.keymaps')
local log = require('opencomplete.log')

-- Setup the plugin
function M.setup(opts)
  -- Check Neovim version
  if vim.fn.has('nvim-0.10') ~= 1 then
    vim.notify('opencomplete.nvim requires Neovim 0.10+', vim.log.levels.ERROR)
    return
  end

  -- Initialize config
  config.setup(opts)

  -- Set log level
  log.level = config.options.log_level or 'info'

  -- Create highlight group
  local color = config.options.color
  vim.api.nvim_set_hl(0, 'OpenCompleteGhost', {
    fg = color.suggestion_color,
    ctermfg = color.cterm,
    default = true,
  })

  -- Setup keymaps
  keymaps.setup()

  -- Setup autocmds
  events.setup()

  -- Setup user commands
  M.setup_commands()

  -- Check server health on startup (async)
  server.check_health(function(status)
    if status.connected then
      log.info('Connected to server (providers: %s)', 
        table.concat(vim.tbl_map(function(p) return p.id end, status.providers), ', '))
      -- Warmup the model in background so first completion is fast
      server.warmup()
    else
      log.warn('Server not available: %s', status.error or 'unknown error')
    end
  end)
end

-- Setup user commands
function M.setup_commands()
  vim.api.nvim_create_user_command('OpenComplete', function(opts)
    local args = vim.split(opts.args, '%s+')
    local subcmd = args[1] or ''

    if subcmd == 'status' then
      M.print_status()
    elseif subcmd == 'enable' then
      M.enable()
      vim.notify('OpenComplete enabled')
    elseif subcmd == 'disable' then
      M.disable()
      vim.notify('OpenComplete disabled')
    elseif subcmd == 'toggle' then
      M.toggle()
      vim.notify('OpenComplete ' .. (M.is_enabled() and 'enabled' or 'disabled'))
    elseif subcmd == 'health' then
      server.check_health(function(status)
        if status.connected then
          vim.notify('OpenComplete: connected')
        else
          vim.notify('OpenComplete: ' .. (status.error or 'disconnected'), vim.log.levels.ERROR)
        end
      end)
    elseif subcmd == 'debug' then
      log.level = 'debug'
      vim.notify('OpenComplete: debug logging enabled')
    elseif subcmd == 'provider' then
      local provider = args[2]
      if provider then
        vim.g.opencomplete_provider = provider
        vim.notify('OpenComplete: provider set to ' .. provider)
      else
        local current = vim.g.opencomplete_provider or config.options.completion.provider or 'default'
        vim.notify('OpenComplete: current provider is ' .. current)
      end
    else
      vim.notify('Usage: OpenComplete [status|enable|disable|toggle|health|debug|provider <name>]')
    end
  end, {
    nargs = '*',
    complete = function(arg_lead, cmd_line)
      local args = vim.split(cmd_line, '%s+')
      if #args <= 2 then
        return { 'status', 'enable', 'disable', 'toggle', 'health', 'debug', 'provider' }
      elseif args[2] == 'provider' then
        -- Return available providers
        local providers = {}
        for _, p in ipairs(server.status.providers) do
          table.insert(providers, p.id)
        end
        return providers
      end
      return {}
    end,
  })
end

-- Print detailed status
function M.print_status()
  local lines = {
    'OpenComplete Status:',
    '  Enabled: ' .. tostring(completion.enabled),
    '  Server: ' .. (server.is_available() and 'connected' or 'disconnected'),
  }

  if server.status.error then
    table.insert(lines, '  Error: ' .. server.status.error)
  end

  if #server.status.providers > 0 then
    table.insert(lines, '  Providers:')
    for _, p in ipairs(server.status.providers) do
      local default_marker = p.is_default and ' (default)' or ''
      table.insert(lines, '    - ' .. p.id .. ': ' .. p.name .. default_marker)
    end
  end

  table.insert(lines, '  Log level: ' .. log.level)

  vim.notify(table.concat(lines, '\n'))
end

-- Public API

-- Get status string for statusline
function M.status()
  return server.get_status_string()
end

-- Manually trigger a completion
function M.complete()
  completion.request()
end

-- Cancel current completion
function M.cancel()
  completion.cancel()
end

-- Enable completions
function M.enable()
  completion.enable()
end

-- Disable completions
function M.disable()
  completion.disable()
end

-- Toggle completions
function M.toggle()
  completion.toggle()
end

-- Check if completions are enabled
function M.is_enabled()
  return completion.enabled
end

-- Accept current suggestion (for custom keymaps)
function M.accept()
  return preview.accept()
end

-- Clear current suggestion
function M.clear()
  preview.clear()
end

-- Check if there's a suggestion
function M.has_suggestion()
  return preview.has_suggestion()
end

-- Get current suggestion text
function M.get_suggestion()
  return preview.get_text()
end

return M
