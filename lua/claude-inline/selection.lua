---@mod claude-inline.selection Visual selection handling for claude-inline.nvim
---@brief [[
--- Handles capturing and processing visual mode selections.
---@brief ]]

local M = {}

---@class Selection
---@field bufnr number Buffer number
---@field start_line number Start line (1-indexed)
---@field start_col number Start column (0-indexed)
---@field end_line number End line (1-indexed)
---@field end_col number End column (0-indexed)
---@field text string Selected text
---@field mode string Visual mode type ('v', 'V', or '\22' for block)
---@field indentation string Leading whitespace of first line

--- Get the current visual selection
---@return Selection? selection The captured selection or nil
function M.get_visual_selection()
  -- Get visual mode marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- Ensure we have valid positions
  if not start_pos or not end_pos then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local start_line = start_pos[2]
  local start_col = start_pos[3] - 1  -- Convert to 0-indexed
  local end_line = end_pos[2]
  local end_col = end_pos[3] - 1  -- Convert to 0-indexed

  -- Get the visual mode type
  local mode = vim.fn.visualmode()

  -- Handle different visual modes
  local lines
  if mode == 'V' then
    -- Line-wise visual mode
    lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    start_col = 0
    if #lines > 0 then
      end_col = #lines[#lines] - 1
    end
  elseif mode == '\22' then  -- Ctrl-V (block mode)
    -- Block-wise visual mode
    lines = M._get_block_selection(bufnr, start_line, start_col, end_line, end_col)
  else
    -- Character-wise visual mode
    lines = M._get_char_selection(bufnr, start_line, start_col, end_line, end_col)
  end

  if not lines or #lines == 0 then
    return nil
  end

  -- Detect indentation from the first line
  local indentation = ''
  if #lines > 0 then
    indentation = lines[1]:match('^%s*') or ''
  end

  -- Join lines to create the text
  local text = table.concat(lines, '\n')

  return {
    bufnr = bufnr,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
    text = text,
    mode = mode,
    indentation = indentation,
  }
end

--- Get character-wise selection
---@param bufnr number Buffer number
---@param start_line number Start line (1-indexed)
---@param start_col number Start column (0-indexed)
---@param end_line number End line (1-indexed)
---@param end_col number End column (0-indexed)
---@return string[] lines Selected lines
function M._get_char_selection(bufnr, start_line, start_col, end_line, end_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  if #lines == 0 then
    return {}
  end

  -- Adjust for character-wise selection
  if #lines == 1 then
    -- Single line selection
    local line = lines[1]
    -- Handle UTF-8 properly
    local byte_start = vim.fn.byteidx(line, start_col)
    local byte_end = vim.fn.byteidx(line, end_col + 1)
    if byte_start == -1 then byte_start = 0 end
    if byte_end == -1 then byte_end = #line end
    lines[1] = string.sub(line, byte_start + 1, byte_end)
  else
    -- Multi-line selection
    -- First line: from start_col to end
    local first_line = lines[1]
    local byte_start = vim.fn.byteidx(first_line, start_col)
    if byte_start == -1 then byte_start = 0 end
    lines[1] = string.sub(first_line, byte_start + 1)

    -- Last line: from beginning to end_col
    local last_line = lines[#lines]
    local byte_end = vim.fn.byteidx(last_line, end_col + 1)
    if byte_end == -1 then byte_end = #last_line end
    lines[#lines] = string.sub(last_line, 1, byte_end)
  end

  return lines
end

--- Get block-wise selection
---@param bufnr number Buffer number
---@param start_line number Start line (1-indexed)
---@param start_col number Start column (0-indexed)
---@param end_line number End line (1-indexed)
---@param end_col number End column (0-indexed)
---@return string[] lines Selected block lines
function M._get_block_selection(bufnr, start_line, start_col, end_line, end_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local result = {}

  -- Ensure start_col <= end_col for block selection
  if start_col > end_col then
    start_col, end_col = end_col, start_col
  end

  for _, line in ipairs(lines) do
    -- Handle UTF-8 properly for block selection
    local byte_start = vim.fn.byteidx(line, start_col)
    local byte_end = vim.fn.byteidx(line, end_col + 1)

    -- Handle lines shorter than the selection
    if byte_start == -1 then
      table.insert(result, '')
    else
      if byte_end == -1 then byte_end = #line end
      local selected = string.sub(line, byte_start + 1, byte_end)
      table.insert(result, selected)
    end
  end

  return result
end

--- Get selection bounds for replacement
---@param selection Selection The selection object
---@return number start_line Start line (0-indexed for API)
---@return number start_col Start column (0-indexed)
---@return number end_line End line (0-indexed for API)
---@return number end_col End column (0-indexed)
function M.get_selection_bounds(selection)
  local start_line = selection.start_line - 1  -- Convert to 0-indexed
  local end_line = selection.end_line - 1  -- Convert to 0-indexed
  local start_col = selection.start_col
  local end_col = selection.end_col

  -- Adjust bounds based on visual mode
  if selection.mode == 'V' then
    -- Line-wise mode: select full lines
    start_col = 0
    -- Get the length of the last line
    local lines = vim.api.nvim_buf_get_lines(
      selection.bufnr,
      end_line,
      end_line + 1,
      false
    )
    if #lines > 0 then
      end_col = #lines[1]
    end
  elseif selection.mode == '\22' then
    -- Block mode bounds are already correct
  else
    -- Character-wise mode
    -- Adjust end_col to be inclusive
    end_col = end_col + 1
  end

  return start_line, start_col, end_line, end_col
end

--- Apply indentation to text
---@param text string Text to indent
---@param indentation string Indentation string
---@return string indented_text Text with indentation applied
function M.apply_indentation(text, indentation)
  if not indentation or indentation == '' then
    return text
  end

  local lines = vim.split(text, '\n', { plain = true })
  local result = {}

  for i, line in ipairs(lines) do
    if i == 1 then
      -- First line might already have indentation from context
      if not line:match('^%s') then
        table.insert(result, indentation .. line)
      else
        table.insert(result, line)
      end
    elseif line ~= '' then
      -- Subsequent non-empty lines
      table.insert(result, indentation .. line)
    else
      -- Empty lines
      table.insert(result, line)
    end
  end

  return table.concat(result, '\n')
end

--- Preserve original indentation pattern
---@param original_text string Original selected text
---@param new_text string New text to apply indentation to
---@return string indented_text New text with original indentation pattern
function M.preserve_indentation(original_text, new_text)
  local original_lines = vim.split(original_text, '\n', { plain = true })
  local new_lines = vim.split(new_text, '\n', { plain = true })

  if #original_lines == 0 then
    return new_text
  end

  -- Extract indentation pattern from original
  local indentations = {}
  for _, line in ipairs(original_lines) do
    local indent = line:match('^%s*') or ''
    table.insert(indentations, indent)
  end

  -- Apply indentation pattern to new text
  local result = {}
  for i, line in ipairs(new_lines) do
    local indent = indentations[math.min(i, #indentations)] or ''
    if line ~= '' then
      -- Remove any existing indentation from new line
      local trimmed = line:gsub('^%s*', '')
      table.insert(result, indent .. trimmed)
    else
      table.insert(result, line)
    end
  end

  return table.concat(result, '\n')
end

return M