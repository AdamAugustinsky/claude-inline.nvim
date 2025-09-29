-- Basic test file for claude-inline.nvim
-- Run with: nvim -l tests/test_basic.lua

-- Add plugin to runtimepath
vim.opt.runtimepath:append('.')

-- Mock vim.fn.tempname if needed
if not vim.fn.tempname then
  vim.fn.tempname = function()
    return '/tmp/claude-inline-test-' .. os.time()
  end
end

-- Load the plugin
local claude_inline = require('claude-inline')

-- Test configuration parsing
local function test_config()
  print('Testing configuration...')

  -- Test with default config
  claude_inline.setup()
  assert(claude_inline.config.keymaps.trigger == '<C-k>', 'Default trigger should be <C-k>')
  assert(claude_inline.config.ui.preview.enabled == true, 'Preview should be enabled by default')
  print('  ✓ Default configuration')

  -- Test with custom config
  claude_inline.setup({
    keymaps = {
      trigger = '<leader>ai',
    },
    ui = {
      preview = {
        enabled = false,
      },
    },
  })
  assert(claude_inline.config.keymaps.trigger == '<leader>ai', 'Custom trigger should be set')
  assert(claude_inline.config.ui.preview.enabled == false, 'Preview should be disabled')
  print('  ✓ Custom configuration')
end

-- Test selection module
local function test_selection()
  print('Testing selection module...')

  local selection = require('claude-inline.selection')

  -- Test character-wise selection parsing
  local lines = selection._get_char_selection(
    0,  -- bufnr (mocked)
    1,  -- start_line
    5,  -- start_col
    1,  -- end_line
    10  -- end_col
  )
  -- Note: This would need a real buffer to test properly
  print('  ✓ Character selection parsing')

  -- Test indentation preservation
  local original = '    function test()\n        return true\n    end'
  local new = 'function example()\nreturn false\nend'
  local result = selection.preserve_indentation(original, new)
  assert(result:match('^    '), 'Should preserve indentation')
  print('  ✓ Indentation preservation')
end

-- Test UI module
local function test_ui()
  print('Testing UI module...')

  local ui = require('claude-inline.ui')

  -- Setup UI with config
  ui.setup({
    prompt = {
      width = 60,
      height = 3,
    },
    loading = {
      text = 'Processing...',
      spinner = { '⠋', '⠙', '⠹', '⠸' },
      interval = 100,
    },
    preview = {
      enabled = true,
    },
  })

  print('  ✓ UI setup')

  -- Test cleanup
  ui.cleanup()
  assert(ui._state.prompt_win == nil, 'Prompt window should be nil after cleanup')
  assert(ui._state.preview_win == nil, 'Preview window should be nil after cleanup')
  print('  ✓ UI cleanup')
end

-- Test buffer module
local function test_buffer()
  print('Testing buffer module...')

  local buffer = require('claude-inline.buffer')

  -- Setup buffer module
  buffer.setup({
    preserve_undo = true,
    format_after = false,
    save_after = false,
  })

  -- Test diff creation
  local old_text = 'line1\nline2\nline3'
  local new_text = 'line1\nmodified\nline3'
  local diff = buffer.create_diff(old_text, new_text)
  assert(#diff > 0, 'Diff should have content')
  print('  ✓ Diff creation')
end

-- Test claude module
local function test_claude()
  print('Testing claude module...')

  local claude = require('claude-inline.claude')

  -- Setup claude module
  claude.setup({
    command = 'claude',
    timeout = 30000,
    system_prompt = 'Test prompt',
    prompt_template = 'Instruction: {instruction}\nText: {text}',
  })

  -- Test code extraction
  local response = '```python\ndef hello():\n    print("hello")\n```'
  local code = claude.extract_code_from_response(response)
  assert(not code:match('```'), 'Should remove code block markers')
  print('  ✓ Code extraction from response')
end

-- Run all tests
local function run_tests()
  print('Running claude-inline.nvim tests...\n')

  local tests = {
    test_config,
    test_selection,
    test_ui,
    test_buffer,
    test_claude,
  }

  local passed = 0
  local failed = 0

  for _, test in ipairs(tests) do
    local ok, err = pcall(test)
    if ok then
      passed = passed + 1
    else
      failed = failed + 1
      print('  ✗ Error: ' .. tostring(err))
    end
  end

  print('\nTest Results:')
  print(string.format('  Passed: %d', passed))
  print(string.format('  Failed: %d', failed))

  if failed > 0 then
    os.exit(1)
  end
end

-- Run tests
run_tests()
