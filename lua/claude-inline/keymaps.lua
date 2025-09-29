---@mod claude-inline.keymaps Keymap registration for claude-inline.nvim
---@brief [[
--- Handles keymap registration for the plugin.
---@brief ]]

local M = {}

--- Register keymaps for the plugin
---@param plugin table Main plugin module
---@param config table Keymaps configuration
function M.register(plugin, config)
  -- Main trigger keymap in visual mode
  if config.trigger then
    vim.keymap.set('v', config.trigger, function()
      plugin.edit()
    end, {
      desc = 'Claude Inline: Edit selection',
      silent = true,
    })
  end

  -- Optional: Register with which-key if available
  vim.defer_fn(function()
    local ok, which_key = pcall(require, 'which-key')
    if ok and which_key.add then
      local mappings = {}

      if config.trigger then
        table.insert(mappings, {
          mode = 'v',
          { config.trigger, desc = 'Claude Inline: Edit selection', icon = '󰚩' },
        })
      end

      if #mappings > 0 then
        which_key.add(mappings)
      end
    end
  end, 100)
end

return M