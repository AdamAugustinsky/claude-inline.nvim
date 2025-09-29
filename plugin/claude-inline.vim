" claude-inline.nvim - Cursor-style CMD+K inline AI editing for Neovim
" Maintainer: Your Name
" Version: 0.1.0

if exists('g:loaded_claude_inline')
  finish
endif
let g:loaded_claude_inline = 1

" Ensure Neovim version compatibility
if !has('nvim-0.7.0')
  echohl WarningMsg
  echom 'claude-inline.nvim requires Neovim 0.7.0 or later'
  echohl None
  finish
endif

" Plugin has been loaded, Lua setup will be called by user