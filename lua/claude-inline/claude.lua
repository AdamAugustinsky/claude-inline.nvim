---@mod claude-inline.claude Claude CLI integration for claude-inline.nvim
---@brief [[
--- Handles communication with the Claude Code CLI for processing text edits.
---@brief ]]

local M = {}

-- Module state
M._state = {
  config = nil,
  job_id = nil,
}

--- Setup the Claude module with configuration
---@param config table Claude configuration
function M.setup(config)
  M._state.config = config
end

--- Build the prompt for Claude
---@param context table Context containing text, instruction, filetype, filename
---@return string prompt The formatted prompt
local function build_prompt(context)
  local config = M._state.config
  local template = config.prompt_template

  -- Replace placeholders in template
  local prompt = template
    :gsub('{instruction}', context.instruction or '')
    :gsub('{text}', context.text or '')
    :gsub('{filetype}', context.filetype or '')
    :gsub('{filename}', context.filename or '')

  return prompt
end

--- Build command arguments for Claude CLI
---@param config table Claude configuration
---@return string[] args Command arguments
local function build_command_args(config)
  local args = {}

  -- Add model if specified
  if config.model then
    table.insert(args, '--model')
    table.insert(args, config.model)
  end

  -- Add max tokens if specified
  if config.max_tokens then
    table.insert(args, '--max-tokens')
    table.insert(args, tostring(config.max_tokens))
  end

  -- Add temperature if specified
  if config.temperature then
    table.insert(args, '--temperature')
    table.insert(args, tostring(config.temperature))
  end

  -- Add system prompt
  if config.system_prompt then
    table.insert(args, '--system')
    table.insert(args, config.system_prompt)
  end

  return args
end

--- Process text with Claude
---@param context table Context containing text, instruction, filetype, filename
---@param callback function Callback with (success, result)
function M.process(context, callback)
  local config = M._state.config

  -- Build the full prompt
  local prompt = build_prompt(context)

  -- Build command and arguments
  local cmd = config.command
  local args = build_command_args(config)

  -- Create temporary file for the prompt (to handle multi-line input safely)
  local tmpfile = vim.fn.tempname()
  local file = io.open(tmpfile, 'w')
  if not file then
    callback(false, 'Failed to create temporary file')
    return
  end

  file:write(prompt)
  file:close()

  -- Prepare output buffer
  local output = {}
  local error_output = {}

  -- Start the job
  M._state.job_id = vim.fn.jobstart({cmd, unpack(args)}, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(error_output, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      M._state.job_id = nil

      -- Clean up temp file
      vim.fn.delete(tmpfile)

      if exit_code == 0 then
        local result = table.concat(output, '\n')
        -- Extract only the code portion (remove any explanation)
        result = M.extract_code_from_response(result)
        callback(true, result)
      else
        local error_msg = table.concat(error_output, '\n')
        if error_msg == '' then
          error_msg = 'Claude CLI failed with exit code: ' .. exit_code
        end
        callback(false, error_msg)
      end
    end,
  })

  -- Check if job started successfully
  if M._state.job_id <= 0 then
    callback(false, 'Failed to start Claude CLI')
    vim.fn.delete(tmpfile)
    return
  end

  -- Send the prompt via stdin
  vim.fn.chansend(M._state.job_id, prompt)
  vim.fn.chanclose(M._state.job_id, 'stdin')

  -- Set up timeout
  if config.timeout and config.timeout > 0 then
    vim.defer_fn(function()
      if M._state.job_id then
        vim.fn.jobstop(M._state.job_id)
        M._state.job_id = nil
        vim.fn.delete(tmpfile)
        callback(false, 'Claude CLI timeout')
      end
    end, config.timeout)
  end
end

--- Extract code from Claude's response
---@param response string The full response from Claude
---@return string code The extracted code
function M.extract_code_from_response(response)
  -- Remove markdown code blocks if present
  local code = response

  -- Check for code blocks with language specifier
  local pattern = '```%w*\n(.-)\n```'
  local extracted = response:match(pattern)
  if extracted then
    code = extracted
  else
    -- Check for code blocks without language specifier
    pattern = '```\n(.-)\n```'
    extracted = response:match(pattern)
    if extracted then
      code = extracted
    end
  end

  -- Remove any leading/trailing explanation text
  -- Look for patterns that indicate explanatory text
  local lines = vim.split(code, '\n', { plain = true })
  local code_lines = {}
  local in_code = false

  for _, line in ipairs(lines) do
    -- Skip lines that look like explanations
    if not line:match('^Here') and
       not line:match('^This') and
       not line:match('^The') and
       not line:match('^I[\'"]') and
       not line:match('^Note:') and
       not line:match('^Explanation:') then
      -- Start collecting when we hit something that looks like code
      if line:match('%S') or in_code then
        in_code = true
        table.insert(code_lines, line)
      end
    end
  end

  if #code_lines > 0 then
    code = table.concat(code_lines, '\n')
  end

  return code
end

--- Cancel any running Claude process
function M.cancel()
  if M._state.job_id then
    vim.fn.jobstop(M._state.job_id)
    M._state.job_id = nil
  end
end

--- Alternative: Use Claude API directly via curl (if API key is available)
---@param context table Context for the edit
---@param callback function Callback with result
function M.process_with_api(context, callback)
  local api_key = vim.env.ANTHROPIC_API_KEY
  if not api_key then
    -- Fall back to CLI
    return M.process(context, callback)
  end

  local config = M._state.config
  local prompt = build_prompt(context)

  -- Build API request
  local request = {
    model = config.model or 'claude-3-sonnet-20240229',
    max_tokens = config.max_tokens or 4096,
    temperature = config.temperature or 0.7,
    system = config.system_prompt,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
  }

  -- Convert to JSON
  local json_data = vim.fn.json_encode(request)

  -- Create curl command
  local curl_cmd = {
    'curl',
    '-X', 'POST',
    'https://api.anthropic.com/v1/messages',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-key: ' .. api_key,
    '-H', 'anthropic-version: 2023-06-01',
    '-d', json_data,
    '--silent',
    '--show-error',
  }

  local output = {}
  local error_output = {}

  vim.fn.jobstart(curl_cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(error_output, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        local response_text = table.concat(output, '\n')
        local ok, response = pcall(vim.fn.json_decode, response_text)

        if ok and response.content and response.content[1] then
          local result = response.content[1].text
          result = M.extract_code_from_response(result)
          callback(true, result)
        else
          callback(false, 'Failed to parse API response')
        end
      else
        local error_msg = table.concat(error_output, '\n')
        callback(false, error_msg)
      end
    end,
  })
end

return M