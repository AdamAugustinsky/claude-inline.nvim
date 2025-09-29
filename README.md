# claude-inline.nvim

A Neovim plugin that brings Cursor-style CMD+K inline AI editing to Neovim using Claude AI through the Claude Code CLI.

## Features

- 🎯 **Visual Mode Editing**: Select text in any visual mode (character, line, or block) and apply AI-powered edits
- 💬 **Inline Prompts**: Floating window interface for entering edit instructions
- 👁️ **Preview Changes**: Optional diff preview before applying changes
- 🔄 **Smart Indentation**: Preserves original indentation patterns
- ⚡ **Fast Integration**: Direct integration with Claude Code CLI
- 🎨 **Customizable UI**: Configurable floating windows, borders, and highlights
- ↩️ **Undo Support**: Preserves undo history for easy rollback

## Requirements

- Neovim 0.7.0 or later
- [Claude Code CLI](https://github.com/anthropics/claude-code) installed and available in PATH
- (Optional) Anthropic API key for direct API access

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'claude-inline.nvim',
  config = function()
    require('claude-inline').setup({
      -- your configuration
    })
  end,
  keys = {
    { '<C-k>', mode = 'v', desc = 'Claude Inline Edit' },
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'claude-inline.nvim',
  config = function()
    require('claude-inline').setup({
      -- your configuration
    })
  end
}
```

## Usage

1. Select text in visual mode (v, V, or Ctrl-V)
2. Press `<C-k>` (default keybinding)
3. Type your instruction in the floating prompt
4. Press `<CR>` to apply the edit or `<Esc>` to cancel
5. If preview is enabled, review changes and press `<CR>` to accept or `<Esc>` to reject

### Example Instructions

- "Convert this to TypeScript"
- "Add error handling"
- "Refactor to use async/await"
- "Add JSDoc comments"
- "Make this more idiomatic"
- "Optimize this algorithm"

## Configuration

### Default Configuration

```lua
require('claude-inline').setup({
  -- Keymap configuration
  keymaps = {
    trigger = '<C-k>',          -- Trigger inline edit in visual mode
    accept = '<CR>',            -- Accept AI suggestion
    cancel = '<Esc>',           -- Cancel operation
    preview_scroll_up = '<C-u>',    -- Scroll up in preview
    preview_scroll_down = '<C-d>',  -- Scroll down in preview
  },

  -- UI configuration
  ui = {
    -- Prompt window settings
    prompt = {
      relative = 'cursor',
      position = 'bottom',
      width = 60,
      height = 3,
      border = 'rounded',
      title = ' Claude Inline Edit ',
      title_pos = 'center',
      footer = ' <CR>: Accept | <Esc>: Cancel ',
      footer_pos = 'center',
      highlight = {
        border = 'FloatBorder',
        title = 'Title',
        footer = 'Comment',
      },
    },

    -- Preview window settings
    preview = {
      enabled = true,           -- Enable preview window
      diff = true,              -- Show diff view
      relative = 'editor',
      width = '80%',
      height = '60%',
      border = 'rounded',
      title = ' Preview Changes ',
      title_pos = 'center',
    },

    -- Loading indicator
    loading = {
      text = '󰔟 Processing with Claude...',
      spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
      interval = 100,  -- milliseconds
    },
  },

  -- Claude CLI configuration
  claude = {
    command = 'claude',         -- Claude CLI command
    model = nil,                -- Model to use (nil = Claude's default)
    timeout = 30000,            -- Timeout in milliseconds
  },

  -- Buffer operation settings
  buffer = {
    preserve_undo = true,       -- Preserve undo history
    format_after = false,       -- Run formatter after applying edit
    save_after = false,         -- Save buffer after applying edit
  },

  -- Debug settings
  debug = {
    enabled = false,
    log_file = vim.fn.stdpath('cache') .. '/claude-inline.log',
  },
})
```

### Minimal Configuration

```lua
require('claude-inline').setup({
  keymaps = {
    trigger = '<leader>ai',  -- Use leader key instead
  },
  ui = {
    preview = {
      enabled = false,       -- Disable preview for faster workflow
    },
  },
})
```

### Advanced Configuration

```lua
require('claude-inline').setup({
  claude = {
    command = 'claude',
    model = 'sonnet',                      -- Use model alias like 'sonnet' or 'opus'
    timeout = 60000,                      -- Longer timeout for complex edits

    -- Custom system prompt (appends to Claude's default)
    system_prompt = [[You are an expert programmer.
When editing code, maintain the existing style and conventions.
Be concise and only return the modified code.]],

    -- Custom prompt template
    prompt_template = [[Language: {filetype}
File: {filename}

Original Code:
{text}

Task: {instruction}

Modified Code:]],
  },

  buffer = {
    preserve_undo = true,
    format_after = true,    -- Auto-format after applying edits
    save_after = true,      -- Auto-save after applying edits
  },
})
```

## Commands

- `:ClaudeInlineEdit` - Trigger inline edit (works in visual mode)
- `:ClaudeInlineCancel` - Cancel current edit operation

## API

The plugin exposes the following API for advanced usage:

```lua
local claude_inline = require('claude-inline')

-- Trigger edit programmatically
claude_inline.edit({
  -- optional parameters
})

-- Cancel current operation
claude_inline.cancel()

-- Get plugin version
claude_inline.get_version()
```

## Customization

### Custom Keymaps

You can disable default keymaps and set your own:

```lua
require('claude-inline').setup({
  keymaps = {
    trigger = false,  -- Disable default keymap
  },
})

-- Set custom keymap
vim.keymap.set('v', '<leader>ce', function()
  require('claude-inline').edit()
end, { desc = 'Claude Edit' })
```

### Integration with Which-key

The plugin automatically registers with which-key if available:

```lua
-- Keymaps will appear in which-key with descriptions and icons
```

### Using with Anthropic API

If you have an Anthropic API key, the plugin can use it directly:

```bash
export ANTHROPIC_API_KEY="your-api-key"
```

The plugin will automatically detect and use the API key for faster responses.

## Tips

1. **Be Specific**: Clear, specific instructions yield better results
2. **Context Matters**: The plugin sends filetype and filename for context
3. **Preserve Style**: Claude tries to match your existing code style
4. **Use Preview**: Review changes before applying, especially for complex edits
5. **Undo is Your Friend**: All edits can be undone with regular Neovim undo

## Troubleshooting

### Enable Debug Logging

```lua
require('claude-inline').setup({
  debug = {
    enabled = true,
  },
})
```

Check logs at: `~/.cache/nvim/claude-inline.log`

### Common Issues

- **Claude CLI not found**: Ensure `claude` is in your PATH
- **Timeout errors**: Increase the timeout in configuration
- **API rate limits**: Use a longer timeout or reduce request frequency

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Inspired by [Cursor](https://cursor.sh/)'s CMD+K feature
- Built on top of [Claude Code CLI](https://github.com/anthropics/claude-code)
- Thanks to the Neovim community for the amazing editor

## Related Projects

- [claude-code.nvim](https://github.com/anthropics/claude-code.nvim) - Terminal interface for Claude Code in Neovim
- [copilot.vim](https://github.com/github/copilot.vim) - GitHub Copilot for Vim/Neovim
- [codeium.vim](https://github.com/Exafunction/codeium.vim) - Free AI code completion# claude-inline.nvim
