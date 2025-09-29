---@mod claude-inline.config Configuration management for claude-inline.nvim
---@brief [[
--- Handles configuration parsing, validation, and defaults for the plugin.
---@brief ]]

local M = {}

--- Default configuration
M.defaults = {
  -- Keymap configuration
  keymaps = {
    trigger = '<C-k>',        -- Trigger inline edit in visual mode
    accept = '<CR>',          -- Accept AI suggestion
    cancel = '<Esc>',         -- Cancel operation
    preview_scroll_up = '<C-u>',   -- Scroll up in preview
    preview_scroll_down = '<C-d>', -- Scroll down in preview
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
      enabled = true,
      diff = true,              -- Show diff view
      relative = 'editor',
      width = '80%',
      height = '60%',
      border = 'rounded',
      title = ' Preview Changes ',
      title_pos = 'center',
      highlight = {
        border = 'FloatBorder',
        title = 'Title',
        added = 'DiffAdd',
        removed = 'DiffDelete',
        changed = 'DiffChange',
      },
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
    command = 'claude',       -- Claude CLI command
    model = nil,              -- Model to use (nil = use Claude's default)
    timeout = 30000,          -- Timeout in milliseconds
    max_tokens = 4096,        -- Maximum tokens in response
    temperature = 0.7,        -- Temperature for generation
    system_prompt = [[You are an AI coding assistant. The user will provide you with selected code and an instruction.
Your task is to modify the selected code according to the instruction.
Return ONLY the modified code without any explanation, markdown formatting, or code blocks.
Preserve the original formatting and indentation as much as possible.]],
    -- Template for the prompt sent to Claude
    -- Available placeholders: {instruction}, {text}, {filetype}, {filename}
    prompt_template = [[File: {filename}
Language: {filetype}

Selected code:
{text}

Instruction: {instruction}

Please provide the modified code:]],
  },

  -- Buffer operation settings
  buffer = {
    preserve_undo = true,     -- Preserve undo history
    format_after = false,     -- Run formatter after applying edit
    save_after = false,       -- Save buffer after applying edit
  },

  -- Debugging and logging
  debug = {
    enabled = false,          -- Enable debug logging
    log_file = vim.fn.stdpath('cache') .. '/claude-inline.log',
  },
}

--- Merge user config with defaults
---@param user_config? table User configuration
---@return table config Merged configuration
local function merge_config(user_config)
  user_config = user_config or {}
  return vim.tbl_deep_extend('force', M.defaults, user_config)
end

--- Validate configuration
---@param config table Configuration to validate
---@return boolean valid Whether configuration is valid
---@return string? error Error message if invalid
local function validate_config(config)
  -- Validate keymaps
  if type(config.keymaps) ~= 'table' then
    return false, 'keymaps must be a table'
  end

  -- Validate UI settings
  if type(config.ui) ~= 'table' then
    return false, 'ui must be a table'
  end

  if config.ui.prompt then
    if type(config.ui.prompt.width) ~= 'number' and type(config.ui.prompt.width) ~= 'string' then
      return false, 'ui.prompt.width must be a number or percentage string'
    end
    if type(config.ui.prompt.height) ~= 'number' then
      return false, 'ui.prompt.height must be a number'
    end
  end

  -- Validate Claude settings
  if type(config.claude) ~= 'table' then
    return false, 'claude must be a table'
  end

  if type(config.claude.command) ~= 'string' then
    return false, 'claude.command must be a string'
  end

  if type(config.claude.timeout) ~= 'number' or config.claude.timeout <= 0 then
    return false, 'claude.timeout must be a positive number'
  end

  -- Validate buffer settings
  if type(config.buffer) ~= 'table' then
    return false, 'buffer must be a table'
  end

  return true
end

--- Parse and validate user configuration
---@param user_config? table User configuration
---@return table config Parsed and validated configuration
function M.parse(user_config)
  local config = merge_config(user_config)

  -- Validate configuration
  local valid, err = validate_config(config)
  if not valid then
    vim.notify('Claude Inline: Invalid configuration: ' .. err, vim.log.levels.ERROR)
    -- Return defaults on error
    return M.defaults
  end

  -- Process percentage values for UI dimensions
  if config.ui.prompt.width and type(config.ui.prompt.width) == 'string' then
    local percentage = config.ui.prompt.width:match('^(%d+)%%$')
    if percentage then
      config.ui.prompt._width_percentage = tonumber(percentage) / 100
    end
  end

  if config.ui.preview.width and type(config.ui.preview.width) == 'string' then
    local percentage = config.ui.preview.width:match('^(%d+)%%$')
    if percentage then
      config.ui.preview._width_percentage = tonumber(percentage) / 100
    end
  end

  if config.ui.preview.height and type(config.ui.preview.height) == 'string' then
    local percentage = config.ui.preview.height:match('^(%d+)%%$')
    if percentage then
      config.ui.preview._height_percentage = tonumber(percentage) / 100
    end
  end

  -- Setup debug logging if enabled
  if config.debug.enabled then
    M._setup_debug_logging(config.debug.log_file)
  end

  return config
end

--- Setup debug logging
---@param log_file string Path to log file
function M._setup_debug_logging(log_file)
  -- Create log directory if it doesn't exist
  local log_dir = vim.fn.fnamemodify(log_file, ':h')
  vim.fn.mkdir(log_dir, 'p')

  -- Override vim.notify for debug messages
  local original_notify = vim.notify
  vim.notify = function(msg, level, opts)
    if type(msg) == 'string' and msg:match('^Claude Inline:') then
      -- Write to log file
      local file = io.open(log_file, 'a')
      if file then
        local timestamp = os.date('%Y-%m-%d %H:%M:%S')
        local level_str = level and vim.log.levels[level] or 'INFO'
        file:write(string.format('[%s] [%s] %s\n', timestamp, level_str, msg))
        file:close()
      end
    end
    -- Call original notify
    original_notify(msg, level, opts)
  end
end

return M