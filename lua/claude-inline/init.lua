---@mod claude-inline Claude Inline Edit for Neovim
---@brief [[
--- A Cursor-style CMD+K inline AI editing plugin for Neovim.
--- Provides visual mode text editing with Claude AI through the Claude Code CLI.
---
--- Usage:
--- 1. Select text in visual mode
--- 2. Press trigger keybinding (default: <C-k>)
--- 3. Type your instruction in the prompt
--- 4. Press Enter to apply AI edits
---@brief ]]

local M = {}

-- Module dependencies
local config = require('claude-inline.config')
local selection = require('claude-inline.selection')
local ui = require('claude-inline.ui')
local claude = require('claude-inline.claude')
local buffer = require('claude-inline.buffer')
local keymaps = require('claude-inline.keymaps')

-- Plugin state
M._state = {
  active = false,
  current_selection = nil,
  prompt_win = nil,
  preview_win = nil,
}

--- Get plugin version
---@return string version Current plugin version
function M.get_version()
  return "0.1.0"
end

--- Main entry point for inline editing
---@param opts? table Optional parameters for the edit operation
function M.edit(opts)
  opts = opts or {}

  -- Check if we're in visual mode
  local mode = vim.api.nvim_get_mode().mode
  if not (mode:match('^[vV]') or mode == '\22') then -- \22 is Ctrl-V
    vim.notify('Claude Inline: Must be in visual mode', vim.log.levels.WARN)
    return
  end

  -- Capture the current selection
  local sel = selection.get_visual_selection()
  if not sel then
    vim.notify('Claude Inline: Failed to capture selection', vim.log.levels.ERROR)
    return
  end

  M._state.current_selection = sel
  M._state.active = true

  -- Exit visual mode
  vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))

  -- Show the prompt UI
  ui.show_prompt(function(instruction)
    if not instruction or instruction == '' then
      M.cancel()
      return
    end

    -- Process with Claude
    M.process_edit(instruction)
  end)
end

--- Process the edit with Claude AI
---@param instruction string The user's instruction for editing
function M.process_edit(instruction)
  if not M._state.current_selection then
    vim.notify('Claude Inline: No active selection', vim.log.levels.ERROR)
    return
  end

  local sel = M._state.current_selection

  -- Show loading indicator
  ui.show_loading()

  -- Build context for Claude
  local context = {
    text = sel.text,
    instruction = instruction,
    filetype = vim.bo[sel.bufnr].filetype,
    filename = vim.api.nvim_buf_get_name(sel.bufnr),
  }

  -- Send to Claude
  claude.process(context, function(success, result)
    ui.hide_loading()

    if not success then
      vim.notify('Claude Inline: ' .. (result or 'Unknown error'), vim.log.levels.ERROR)
      M.cancel()
      return
    end

    -- Apply the edit
    M.apply_edit(result)
  end)
end

--- Apply the AI-generated edit to the buffer
---@param new_text string The new text to replace the selection with
function M.apply_edit(new_text)
  if not M._state.current_selection then
    return
  end

  local sel = M._state.current_selection

  -- Show preview if configured
  if M.config.ui.preview.enabled then
    ui.show_preview(sel.text, new_text, function(accepted)
      if accepted then
        buffer.replace_selection(sel, new_text)
        vim.notify('Claude Inline: Edit applied', vim.log.levels.INFO)
      end
      M.cleanup()
    end)
  else
    -- Apply directly without preview
    buffer.replace_selection(sel, new_text)
    vim.notify('Claude Inline: Edit applied', vim.log.levels.INFO)
    M.cleanup()
  end
end

--- Cancel the current edit operation
function M.cancel()
  M.cleanup()
  vim.notify('Claude Inline: Edit cancelled', vim.log.levels.INFO)
end

--- Clean up plugin state
function M.cleanup()
  ui.cleanup()
  M._state.active = false
  M._state.current_selection = nil
end

--- Setup the plugin with user configuration
---@param user_config? table User configuration table
function M.setup(user_config)
  -- Parse and merge configuration
  M.config = config.parse(user_config)

  -- Initialize modules
  ui.setup(M.config.ui)
  claude.setup(M.config.claude)
  buffer.setup(M.config.buffer)

  -- Register keymaps
  keymaps.register(M, M.config.keymaps)

  -- Create user commands
  vim.api.nvim_create_user_command('ClaudeInlineEdit', function(args)
    M.edit(args)
  end, {
    desc = 'Trigger Claude inline edit',
    range = true,
  })

  vim.api.nvim_create_user_command('ClaudeInlineCancel', function()
    M.cancel()
  end, {
    desc = 'Cancel current Claude inline edit',
  })
end

return M