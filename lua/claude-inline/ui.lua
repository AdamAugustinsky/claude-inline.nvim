---@mod claude-inline.ui User interface components for claude-inline.nvim
---@brief [[
--- Provides floating window UI components for prompts, previews, and loading indicators.
---@brief ]]

local M = {}

-- UI state
M._state = {
  prompt_win = nil,
  prompt_buf = nil,
  preview_win = nil,
  preview_buf = nil,
  loading_win = nil,
  loading_buf = nil,
  loading_timer = nil,
  spinner_index = 1,
  config = nil,
}

--- Setup UI module with configuration
---@param config table UI configuration
function M.setup(config)
  M._state.config = config
end

--- Calculate window dimensions from config
---@param win_config table Window configuration
---@param container_width number Container width
---@param container_height number Container height
---@return number width Calculated width
---@return number height Calculated height
local function calculate_dimensions(win_config, container_width, container_height)
  local width = win_config.width
  local height = win_config.height

  -- Handle percentage-based width
  if win_config._width_percentage then
    width = math.floor(container_width * win_config._width_percentage)
  elseif type(width) == 'string' and width:match('%d+%%') then
    local pct = tonumber(width:match('(%d+)%%')) / 100
    width = math.floor(container_width * pct)
  end

  -- Handle percentage-based height
  if win_config._height_percentage then
    height = math.floor(container_height * win_config._height_percentage)
  elseif type(height) == 'string' and height:match('%d+%%') then
    local pct = tonumber(height:match('(%d+)%%')) / 100
    height = math.floor(container_height * pct)
  end

  return width, height
end

--- Create a floating window
---@param config table Window configuration
---@param buf? number Optional existing buffer to use
---@return number win Window ID
---@return number buf Buffer ID
local function create_float_win(config, buf)
  -- Create buffer if not provided
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  end

  -- Get editor dimensions
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight

  -- Calculate window dimensions
  local width, height = calculate_dimensions(config, editor_width, editor_height)

  -- Calculate position
  local row, col
  if config.relative == 'cursor' then
    -- Position relative to cursor
    row = 1
    col = 0
    if config.position == 'top' then
      row = -(height + 1)
    end
  else
    -- Position relative to editor
    row = math.floor((editor_height - height) / 2)
    col = math.floor((editor_width - width) / 2)
  end

  -- Create window config
  local win_config = {
    relative = config.relative or 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = config.border or 'rounded',
    title = config.title,
    title_pos = config.title_pos,
    footer = config.footer,
    footer_pos = config.footer_pos,
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_config)

  -- Apply highlights
  if config.highlight then
    if config.highlight.border then
      vim.api.nvim_set_option_value('winhighlight',
        'FloatBorder:' .. config.highlight.border,
        { win = win })
    end
  end

  return win, buf
end

--- Show the prompt window for user input
---@param callback function Callback with user input
function M.show_prompt(callback)
  if M._state.prompt_win and vim.api.nvim_win_is_valid(M._state.prompt_win) then
    vim.api.nvim_win_close(M._state.prompt_win, true)
  end

  local config = M._state.config.prompt

  -- Create prompt window
  local win, buf = create_float_win(config)
  M._state.prompt_win = win
  M._state.prompt_buf = buf

  -- Set buffer options
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  vim.api.nvim_set_option_value('filetype', 'claude-inline-prompt', { buf = buf })

  -- Focus the window and enter insert mode
  vim.api.nvim_set_current_win(win)
  vim.cmd('startinsert')

  -- Set up autocmd to handle window close
  local group = vim.api.nvim_create_augroup('ClaudeInlinePrompt', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    pattern = tostring(win),
    once = true,
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
      M._state.prompt_win = nil
      M._state.prompt_buf = nil
    end,
  })

  -- Set up keymaps for the prompt buffer
  local opts = { buffer = buf, nowait = true, noremap = true, silent = true }

  -- Accept input
  vim.keymap.set('i', config.accept or '<CR>', function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, '\n'):gsub('^%s*(.-)%s*$', '%1')  -- Trim whitespace

    vim.api.nvim_win_close(win, true)
    M._state.prompt_win = nil
    M._state.prompt_buf = nil

    if callback then
      callback(input)
    end
  end, opts)

  -- Cancel input
  vim.keymap.set({ 'i', 'n' }, config.cancel or '<Esc>', function()
    vim.api.nvim_win_close(win, true)
    M._state.prompt_win = nil
    M._state.prompt_buf = nil

    if callback then
      callback(nil)
    end
  end, opts)
end

--- Show loading indicator
function M.show_loading()
  if M._state.loading_win and vim.api.nvim_win_is_valid(M._state.loading_win) then
    return
  end

  local config = M._state.config.loading

  -- Create a small floating window for loading indicator
  local width = vim.fn.strdisplaywidth(config.text) + 4
  local height = 1

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

  local win_config = {
    relative = 'cursor',
    width = width,
    height = height,
    row = 1,
    col = 0,
    style = 'minimal',
    border = 'rounded',
  }

  local win = vim.api.nvim_open_win(buf, false, win_config)
  M._state.loading_win = win
  M._state.loading_buf = buf

  -- Start spinner animation
  M._state.spinner_index = 1
  M._update_loading_text()

  M._state.loading_timer = vim.uv.new_timer()
  M._state.loading_timer:start(0, config.interval, vim.schedule_wrap(function()
    M._update_loading_text()
  end))
end

--- Update loading indicator text
function M._update_loading_text()
  if not M._state.loading_buf or not vim.api.nvim_buf_is_valid(M._state.loading_buf) then
    M.hide_loading()
    return
  end

  local config = M._state.config.loading
  local spinner = config.spinner[M._state.spinner_index]
  local text = spinner .. ' ' .. config.text

  vim.api.nvim_set_option_value('modifiable', true, { buf = M._state.loading_buf })
  vim.api.nvim_buf_set_lines(M._state.loading_buf, 0, -1, false, { text })
  vim.api.nvim_set_option_value('modifiable', false, { buf = M._state.loading_buf })

  -- Update spinner index
  M._state.spinner_index = M._state.spinner_index % #config.spinner + 1
end

--- Hide loading indicator
function M.hide_loading()
  if M._state.loading_timer then
    M._state.loading_timer:stop()
    M._state.loading_timer:close()
    M._state.loading_timer = nil
  end

  if M._state.loading_win and vim.api.nvim_win_is_valid(M._state.loading_win) then
    vim.api.nvim_win_close(M._state.loading_win, true)
  end

  M._state.loading_win = nil
  M._state.loading_buf = nil
  M._state.spinner_index = 1
end

--- Show preview window with diff
---@param original string Original text
---@param modified string Modified text
---@param callback function Callback with acceptance decision
function M.show_preview(original, modified, callback)
  if M._state.preview_win and vim.api.nvim_win_is_valid(M._state.preview_win) then
    vim.api.nvim_win_close(M._state.preview_win, true)
  end

  local config = M._state.config.preview

  -- Create preview window
  local win, buf = create_float_win(config)
  M._state.preview_win = win
  M._state.preview_buf = buf

  -- Prepare content
  local content = {}

  if config.diff then
    -- Show diff view
    table.insert(content, '--- Original')
    table.insert(content, '+++ Modified')
    table.insert(content, '─────────────────────────────────────')

    -- Simple diff display (could be enhanced with actual diff algorithm)
    local original_lines = vim.split(original, '\n', { plain = true })
    local modified_lines = vim.split(modified, '\n', { plain = true })

    -- Show original with - prefix
    for _, line in ipairs(original_lines) do
      table.insert(content, '- ' .. line)
    end

    table.insert(content, '─────────────────────────────────────')

    -- Show modified with + prefix
    for _, line in ipairs(modified_lines) do
      table.insert(content, '+ ' .. line)
    end
  else
    -- Just show the modified text
    for line in modified:gmatch('[^\n]+') do
      table.insert(content, line)
    end
  end

  -- Set buffer content
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('filetype', 'diff', { buf = buf })

  -- Focus the window
  vim.api.nvim_set_current_win(win)

  -- Set up keymaps for the preview buffer
  local opts = { buffer = buf, nowait = true, noremap = true, silent = true }

  -- Accept changes
  vim.keymap.set('n', '<CR>', function()
    vim.api.nvim_win_close(win, true)
    M._state.preview_win = nil
    M._state.preview_buf = nil
    if callback then
      callback(true)
    end
  end, opts)

  -- Reject changes
  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(win, true)
    M._state.preview_win = nil
    M._state.preview_buf = nil
    if callback then
      callback(false)
    end
  end, opts)

  -- Scrolling
  vim.keymap.set('n', '<C-u>', '<C-u>', opts)
  vim.keymap.set('n', '<C-d>', '<C-d>', opts)
end

--- Clean up all UI elements
function M.cleanup()
  -- Close prompt window
  if M._state.prompt_win and vim.api.nvim_win_is_valid(M._state.prompt_win) then
    vim.api.nvim_win_close(M._state.prompt_win, true)
  end
  M._state.prompt_win = nil
  M._state.prompt_buf = nil

  -- Close preview window
  if M._state.preview_win and vim.api.nvim_win_is_valid(M._state.preview_win) then
    vim.api.nvim_win_close(M._state.preview_win, true)
  end
  M._state.preview_win = nil
  M._state.preview_buf = nil

  -- Hide loading indicator
  M.hide_loading()
end

return M