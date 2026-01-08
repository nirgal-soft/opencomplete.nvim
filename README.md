# opencomplete.nvim

AI-powered inline code completions for Neovim. Fast, local-first, and privacy-friendly.

## Features

- **Ghost text completions** - See suggestions inline as you type
- **Local-first** - Works with Ollama for fast, private completions
- **Cloud option** - Claude support for higher quality when needed
- **Smart detection** - Single-line vs multi-line completions based on context
- **Style hints** - Teach the model your coding conventions

## Requirements

- Neovim 0.10+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [opencomplete-rs](https://github.com/nirgal-soft/opencomplete-rs) server running

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'nirgal-soft/opencomplete.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('opencomplete').setup({})
  end,
}
```

## Configuration

```lua
require('opencomplete').setup({
  server = {
    host = '127.0.0.1',
    port = 8642,
  },
  completion = {
    debounce_ms = 75,
    max_tokens = 256,
  },
  keymaps = {
    accept_suggestion = '<C-j>',
  },
  ignore_filetypes = {
    TelescopePrompt = true,
  },
  filetype_style_hints = {
    rust = '2-space indent, trailing commas',
    python = 'PEP8, 4-space indent',
  },
})
```

## Keymaps

| Key | Action |
|-----|--------|
| `<C-j>` | Accept suggestion |

## Commands

| Command | Description |
|---------|-------------|
| `:OpenComplete status` | Show connection status |
| `:OpenComplete enable` | Enable completions |
| `:OpenComplete disable` | Disable completions |
| `:OpenComplete toggle` | Toggle completions |

## License

MIT
