local M = {}

M.defaults = {
  server = {
    host = '127.0.0.1',
    port = 8642,
  },
  completion = {
    debounce_ms = 75,
    max_tokens = 128,
    provider = nil,
    style_hints = nil,  -- Global style hints (string or nil)
  },
  -- Per-filetype style hints (overrides global)
  -- Example: { rust = "tabwidth=4, no trailing commas", python = "PEP8, 4-space indent" }
  filetype_style_hints = {},
  keymaps = {
    accept_suggestion = '<C-j>',
  },
  ignore_filetypes = {},
  color = {
    suggestion_color = '#ffffff',
    cterm = 244,
  },
  disable_keymaps = false,
  condition = nil,
  log_level = 'info',  -- 'debug', 'info', 'warn', 'error', 'off'
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', {}, M.defaults, opts or {})
end

function M.get_base_url()
  return string.format('http://%s:%d', M.options.server.host, M.options.server.port)
end

function M.is_filetype_ignored(ft)
  return M.options.ignore_filetypes[ft] == true
end

function M.should_complete()
  -- Check filetype
  local ft = vim.bo.filetype
  if M.is_filetype_ignored(ft) then
    return false
  end

  -- Check user condition
  if M.options.condition and type(M.options.condition) == 'function' then
    if M.options.condition() then
      return false
    end
  end

  return true
end

-- Get style hints for a filetype
-- Priority: 1. vim.g.opencomplete_style_hints (runtime override)
--           2. filetype_style_hints[ft] (per-filetype config)
--           3. completion.style_hints (global config)
function M.get_style_hints(ft)
  -- Check for runtime global override
  if vim.g.opencomplete_style_hints then
    return vim.g.opencomplete_style_hints
  end

  -- Check for per-filetype config
  if ft and M.options.filetype_style_hints[ft] then
    return M.options.filetype_style_hints[ft]
  end

  -- Fall back to global config
  return M.options.completion.style_hints
end

return M
