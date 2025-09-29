---@mod claude-inline.buffer Buffer manipulation for claude-inline.nvim
---@brief [[
--- Handles buffer text replacement and undo management.
---@brief ]]

local M = {}

-- Module state
M._state = {
  config = nil,
  undo_sequence = nil,
}

--- Setup buffer module with configuration
---@param config table Buffer configuration
function M.setup(config)
  M._state.config = config
end

--- Replace selected text in buffer
---@param selection table Selection object from selection module
---@param new_text string New text to replace selection with
function M.replace_selection(selection, new_text)
  local config = M._state.config
  local bufnr = selection.bufnr

  -- Check if buffer is still valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify('Claude Inline: Buffer is no longer valid', vim.log.levels.ERROR)
    return
  end

  -- Check if buffer is modifiable
  local modifiable = vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
  if not modifiable then
    vim.notify('Claude Inline: Buffer is not modifiable', vim.log.levels.ERROR)
    return
  end

  -- Get selection bounds
  local selection_module = require('claude-inline.selection')
  local start_line, start_col, end_line, end_col = selection_module.get_selection_bounds(selection)

  -- Preserve indentation if needed
  if selection.indentation and selection.indentation ~= '' then
    new_text = selection_module.preserve_indentation(selection.text, new_text)
  end

  -- Split new text into lines
  local new_lines = vim.split(new_text, '\n', { plain = true })

  -- Handle different visual modes
  if selection.mode == 'V' then
    -- Line-wise replacement
    M._replace_lines(bufnr, start_line, end_line, new_lines, config)
  elseif selection.mode == '\22' then  -- Block mode
    -- Block-wise replacement
    M._replace_block(bufnr, selection, new_lines, config)
  else
    -- Character-wise replacement
    M._replace_chars(bufnr, start_line, start_col, end_line, end_col, new_lines, config)
  end

  -- Format after if configured
  if config.format_after then
    M._format_range(bufnr, start_line, start_line + #new_lines - 1)
  end

  -- Save buffer if configured
  if config.save_after then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd('write')
    end)
  end
end

--- Replace lines in buffer
---@param bufnr number Buffer number
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed)
---@param new_lines string[] New lines to insert
---@param config table Configuration
function M._replace_lines(bufnr, start_line, end_line, new_lines, config)
  -- Start undo sequence if configured
  if config.preserve_undo then
    M._start_undo_sequence()
  end

  -- Replace the lines
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line + 1, false, new_lines)

  -- End undo sequence
  if config.preserve_undo then
    M._end_undo_sequence()
  end
end

--- Replace character-wise selection
---@param bufnr number Buffer number
---@param start_line number Start line (0-indexed)
---@param start_col number Start column (0-indexed)
---@param end_line number End line (0-indexed)
---@param end_col number End column (0-indexed)
---@param new_lines string[] New lines to insert
---@param config table Configuration
function M._replace_chars(bufnr, start_line, start_col, end_line, end_col, new_lines, config)
  -- Start undo sequence if configured
  if config.preserve_undo then
    M._start_undo_sequence()
  end

  -- Get existing lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)

  if #lines == 0 then
    return
  end

  -- Build replacement
  local result = {}

  if start_line == end_line then
    -- Single line replacement
    local line = lines[1]
    local before = string.sub(line, 1, start_col)
    local after = string.sub(line, end_col + 1)

    if #new_lines == 1 then
      -- Single line to single line
      table.insert(result, before .. new_lines[1] .. after)
    else
      -- Multiple lines replacement
      table.insert(result, before .. new_lines[1])
      for i = 2, #new_lines - 1 do
        table.insert(result, new_lines[i])
      end
      table.insert(result, new_lines[#new_lines] .. after)
    end
  else
    -- Multi-line replacement
    -- First line: keep everything before start_col
    local first_line = lines[1]
    local before = string.sub(first_line, 1, start_col)

    -- Last line: keep everything after end_col
    local last_line = lines[#lines]
    local after = string.sub(last_line, end_col + 1)

    if #new_lines == 1 then
      -- Replace with single line
      table.insert(result, before .. new_lines[1] .. after)
    else
      -- Replace with multiple lines
      table.insert(result, before .. new_lines[1])
      for i = 2, #new_lines - 1 do
        table.insert(result, new_lines[i])
      end
      table.insert(result, new_lines[#new_lines] .. after)
    end
  end

  -- Apply the replacement
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line + 1, false, result)

  -- End undo sequence
  if config.preserve_undo then
    M._end_undo_sequence()
  end
end

--- Replace block-wise selection
---@param bufnr number Buffer number
---@param selection table Selection object
---@param new_lines string[] New lines to insert
---@param config table Configuration
function M._replace_block(bufnr, selection, new_lines, config)
  -- Start undo sequence if configured
  if config.preserve_undo then
    M._start_undo_sequence()
  end

  local start_line = selection.start_line - 1  -- Convert to 0-indexed
  local end_line = selection.end_line - 1
  local start_col = selection.start_col
  local end_col = selection.end_col

  -- Ensure start_col <= end_col
  if start_col > end_col then
    start_col, end_col = end_col, start_col
  end

  -- Get existing lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)

  -- Replace block in each line
  for i, line in ipairs(lines) do
    local new_text = new_lines[i] or ''

    -- Get parts of the line
    local before = string.sub(line, 1, start_col)
    local after = string.sub(line, end_col + 2)  -- +2 because end_col is inclusive

    -- Reconstruct line
    lines[i] = before .. new_text .. after
  end

  -- Apply the replacement
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line + 1, false, lines)

  -- End undo sequence
  if config.preserve_undo then
    M._end_undo_sequence()
  end
end

--- Start an undo sequence
function M._start_undo_sequence()
  -- Save current undo sequence number
  M._state.undo_sequence = vim.fn.undotree().seq_cur

  -- Start a new change
  vim.cmd('normal! i')
  vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
end

--- End an undo sequence
function M._end_undo_sequence()
  -- Force write to undo history
  vim.cmd('normal! u')
  vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<C-r>', true, false, true))
end

--- Format a range of lines
---@param bufnr number Buffer number
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed)
function M._format_range(bufnr, start_line, end_line)
  -- Save current window
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)

  -- Find or create a window for the buffer
  local win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      win = w
      break
    end
  end

  if not win then
    -- Create a temporary window
    vim.cmd('split')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
  end

  -- Format the range
  vim.api.nvim_win_call(win, function()
    -- Try LSP formatting first
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    local formatted = false

    for _, client in ipairs(clients) do
      if client.server_capabilities.documentRangeFormattingProvider then
        vim.lsp.buf.format({
          bufnr = bufnr,
          range = {
            ['start'] = { start_line + 1, 0 },
            ['end'] = { end_line + 1, 0 },
          },
          async = false,
        })
        formatted = true
        break
      end
    end

    -- Fall back to using formatexpr or formatprg
    if not formatted then
      vim.cmd(string.format('%d,%dnormal! gq', start_line + 1, end_line + 1))
    end
  end)

  -- Restore original window if we created a temporary one
  if vim.api.nvim_win_get_buf(win) ~= current_buf then
    vim.api.nvim_win_close(win, true)
  end

  -- Restore focus to original window
  vim.api.nvim_set_current_win(current_win)
end

--- Create a diff between old and new text
---@param old_text string Original text
---@param new_text string New text
---@return string[] diff_lines Lines showing the diff
function M.create_diff(old_text, new_text)
  local old_lines = vim.split(old_text, '\n', { plain = true })
  local new_lines = vim.split(new_text, '\n', { plain = true })

  local diff = {}

  -- Simple line-by-line diff (could be enhanced with a proper diff algorithm)
  local max_lines = math.max(#old_lines, #new_lines)

  for i = 1, max_lines do
    local old_line = old_lines[i] or ''
    local new_line = new_lines[i] or ''

    if old_line ~= new_line then
      if old_lines[i] then
        table.insert(diff, '- ' .. old_line)
      end
      if new_lines[i] then
        table.insert(diff, '+ ' .. new_line)
      end
    else
      table.insert(diff, '  ' .. old_line)
    end
  end

  return diff
end

return M