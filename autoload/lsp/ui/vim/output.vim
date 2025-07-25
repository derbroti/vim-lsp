let s:use_vim_popup = has('patch-8.1.1517') && g:lsp_preview_float && !has('nvim')
let s:use_nvim_float = exists('*nvim_open_win') && g:lsp_preview_float && has('nvim')
let s:use_preview = !s:use_vim_popup && !s:use_nvim_float

function! s:import_modules() abort
    if exists('s:Markdown') | return | endif
    let s:Markdown = vital#lsp#import('VS.Vim.Syntax.Markdown')
    let s:MarkupContent = vital#lsp#import('VS.LSP.MarkupContent')
    let s:Window = vital#lsp#import('VS.Vim.Window')
    let s:Text = vital#lsp#import('VS.LSP.Text')
endfunction

let s:winid = v:false
let s:prevwin = v:false
let s:preview_data = v:false

function! s:vim_popup_closed(...) abort
    let s:preview_data = v:false
endfunction

function! lsp#ui#vim#output#closepreview() abort
    if win_getid() ==# s:winid
        " Don't close if window got focus
        return
    endif

    if s:winid == v:false
        return
    endif

    "closing floats in vim8.1 must use popup_close()
    "nvim must use nvim_win_close. pclose is not reliable and does not always work
    if s:use_vim_popup && s:winid
        call popup_close(s:winid)
    elseif s:use_nvim_float && s:winid
        silent! call nvim_win_close(s:winid, 0)
    else
        pclose
    endif
    let s:winid = v:false
    let s:preview_data = v:false
    augroup lsp_float_preview_close
    augroup end
    autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
    doautocmd <nomodeline> User lsp_float_closed
endfunction

function! lsp#ui#vim#output#focuspreview() abort
    if s:is_cmdwin()
        return
    endif

    " This does not work for vim8.1 popup but will work for nvim and old preview
    if s:winid
        if win_getid() !=# s:winid
            let s:prevwin = win_getid()
            call win_gotoid(s:winid)
        elseif s:prevwin
            " Temporarily disable hooks
            " TODO: remove this when closing logic is able to distinguish different move directions
            autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
            call win_gotoid(s:prevwin)
            call s:add_float_closing_hooks()
            let s:prevwin = v:false
        endif
    endif
endfunction

function! s:bufwidth() abort
    let l:width = winwidth(0)
    let l:numberwidth = max([&numberwidth, strlen(line('$'))+1])
    let l:numwidth = (&number || &relativenumber)? l:numberwidth : 0
    let l:foldwidth = &foldcolumn

    if &signcolumn ==? 'yes'
        let l:signwidth = 2
    elseif &signcolumn ==? 'auto'
        let l:signs = execute(printf('sign place buffer=%d', bufnr('')))
        let l:signs = split(l:signs, "\n")
        let l:signwidth = len(l:signs)>2? 2: 0
    else
        let l:signwidth = 0
    endif
    return l:width - l:numwidth - l:foldwidth - l:signwidth
endfunction


function! s:get_float_positioning(height, width) abort
    let l:height = a:height
    let l:width = a:width
    " TODO: add option to configure it 'docked' at the bottom/top/right

    " NOTE: screencol() and screenrow() start from (1,1)
    " but the popup window co-ordinates start from (0,0)
    " Very convenient!
    " For a simple single-line 'tooltip', the following
    " two lines are enough to determine the position

    let l:col = screencol()
    let l:row = screenrow()

    let l:height = min([l:height, max([&lines - &cmdheight - l:row, &previewheight])])

    let l:style = 'minimal'
    let l:border = 'double'
    " Positioning is not window but screen relative
    let l:opts = {
        \ 'relative': 'editor',
        \ 'row': l:row,
        \ 'col': l:col,
        \ 'width': l:width,
        \ 'height': l:height,
        \ 'style': l:style,
        \ 'border': l:border,
        \ }
    return l:opts
endfunction

function! lsp#ui#vim#output#floatingpreview(data) abort
    if s:use_nvim_float
        let l:buf = nvim_create_buf(v:false, v:true)

        " Try to get as much space around the cursor, but at least 10x10
        let l:width = max([s:bufwidth(), 10])
        let l:height = max([&lines - winline() + 1, winline() - 1, 10])

        if g:lsp_preview_max_height > 0
            let l:height = min([g:lsp_preview_max_height, l:height])
        endif

        let l:opts = s:get_float_positioning(l:height, l:width)

        let s:winid = nvim_open_win(l:buf, v:false, l:opts)
        call nvim_win_set_option(s:winid, 'winhl', 'Normal:Pmenu,NormalNC:Pmenu')
        call nvim_win_set_option(s:winid, 'foldenable', v:false)
        call nvim_win_set_option(s:winid, 'wrap', v:true)
        call nvim_win_set_option(s:winid, 'statusline', '')
        call nvim_win_set_option(s:winid, 'number', v:false)
        call nvim_win_set_option(s:winid, 'relativenumber', v:false)
        call nvim_win_set_option(s:winid, 'cursorline', v:false)
        call nvim_win_set_option(s:winid, 'cursorcolumn', v:false)
        call nvim_win_set_option(s:winid, 'colorcolumn', '')
        call nvim_win_set_option(s:winid, 'signcolumn', 'no')
        " Enable closing the preview with esc, but map only in the scratch buffer
        call nvim_buf_set_keymap(l:buf, 'n', '<esc>', ':pclose<cr>', {'silent': v:true})
    elseif s:use_vim_popup
        let l:options = {
            \ 'moved': 'any',
            \ 'border': [0,0,0,0],
            \ 'padding': [0,1,0,1],
            \ 'callback': function('s:vim_popup_closed')
            \ }

        if g:lsp_preview_max_width > 0
            let l:options['maxwidth'] = g:lsp_preview_max_width
        endif

        if g:lsp_preview_max_height > 0
            let l:options['maxheight'] = g:lsp_preview_max_height
        endif

        let s:winid = popup_atcursor('...', l:options)
    endif
    return s:winid
endfunction

function! lsp#ui#vim#output#setcontent(winid, lines, ft) abort
    if s:use_vim_popup
        " vim popup
        call setbufline(winbufnr(a:winid), 1, a:lines)
        call setbufvar(winbufnr(a:winid), '&filetype', a:ft . '.lsp-hover')
    elseif s:use_nvim_float
        " nvim floating
        call nvim_buf_set_lines(winbufnr(a:winid), 0, -1, v:false, a:lines)
        call nvim_buf_set_option(winbufnr(a:winid), 'readonly', v:true)
        call nvim_buf_set_option(winbufnr(a:winid), 'modifiable', v:false)
        call nvim_buf_set_option(winbufnr(a:winid), 'filetype', a:ft.'.lsp-hover')
        call nvim_win_set_cursor(a:winid, [1, 0])
    elseif s:use_preview
        " preview window
        call setbufline(winbufnr(a:winid), 1, a:lines)
        call setbufvar(winbufnr(a:winid), '&filetype', a:ft . '.lsp-hover')
    endif
endfunction

function! lsp#ui#vim#output#adjust_float_placement(bufferlines, maxwidth) abort
    if s:use_nvim_float
        let l:win_config = {}
        let l:height = min([winheight(s:winid), a:bufferlines])
        let l:width = min([winwidth(s:winid), a:maxwidth])
        let l:win_config = s:get_float_positioning(l:height, l:width)
        call nvim_win_set_config(s:winid, l:win_config )
    endif
endfunction

function! s:add_float_closing_hooks() abort
    if g:lsp_preview_autoclose
        augroup lsp_float_preview_close
            autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
            autocmd CursorMoved,CursorMovedI,VimResized * call lsp#ui#vim#output#closepreview()
        augroup END
    endif
endfunction

function! lsp#ui#vim#output#getpreviewwinid() abort
    return s:winid
endfunction

function! s:open_preview(data) abort
    if s:use_vim_popup || s:use_nvim_float
        let l:winid = lsp#ui#vim#output#floatingpreview(a:data)
    else
        execute &previewheight.'new'
        let l:winid = win_getid()
    endif
    return l:winid
endfunction

function! s:set_cursor(current_window_id, options) abort
    if !has_key(a:options, 'cursor')
        return
    endif

    if s:use_nvim_float
        " Neovim floats
        " Go back to the preview window to set the cursor
        call win_gotoid(s:winid)
        let l:old_scrolloff = &scrolloff
        let &scrolloff = 0

        call nvim_win_set_cursor(s:winid, [a:options['cursor']['line'], a:options['cursor']['col']])
        call s:align_preview(a:options)

        " Finally, go back to the original window
        call win_gotoid(a:current_window_id)

        let &scrolloff = l:old_scrolloff
    elseif s:use_vim_popup
        " Vim popups
        function! AlignVimPopup(timer) closure abort
            call s:align_preview(a:options)
        endfunction
        call timer_start(0, function('AlignVimPopup'))
    else
        " Preview
        " Don't use 'scrolloff', it might mess up the cursor's position
        let &l:scrolloff = 0
        call cursor(a:options['cursor']['line'], a:options['cursor']['col'])
        call s:align_preview(a:options)
    endif
endfunction

function! s:align_preview(options) abort
    if !has_key(a:options, 'cursor') ||
        \ !has_key(a:options['cursor'], 'align')
        return
    endif

    let l:align = a:options['cursor']['align']

    if s:use_vim_popup
        " Vim popups
        let l:pos = popup_getpos(s:winid)
        let l:below = winline() < winheight(0) / 2
        if l:below
            let l:height = min([l:pos['core_height'], winheight(0) - winline() - 2])
        else
            let l:height = min([l:pos['core_height'], winline() - 3])
        endif
        let l:width = l:pos['core_width']

        let l:options = {
            \ 'minwidth': l:width,
            \ 'maxwidth': l:width,
            \ 'minheight': l:height,
            \ 'maxheight': l:height,
            \ 'pos': l:below ? 'topleft' : 'botleft',
            \ 'line': l:below ? 'cursor+1' : 'cursor-1'
            \ }

        if l:align ==? 'top'
            let l:options['firstline'] = a:options['cursor']['line']
        elseif l:align ==? 'center'
            let l:options['firstline'] = a:options['cursor']['line'] - (l:height - 1) / 2
        elseif l:align ==? 'bottom'
            let l:options['firstline'] = a:options['cursor']['line'] - l:height + 1
        endif

        call popup_setoptions(s:winid, l:options)
        redraw!
    else
        " Preview and Neovim floats
        if l:align ==? 'top'
            normal! zt
        elseif l:align ==? 'center'
            normal! zz
        elseif l:align ==? 'bottom'
            normal! zb
        endif
    endif
endfunction

function! lsp#ui#vim#output#get_size_info(winid) abort
    " Get size information while still having the buffer active
    let l:buffer = winbufnr(a:winid)
    let l:maxwidth = max(map(getbufline(l:buffer, 1, '$'), 'strdisplaywidth(v:val)'))
    let l:bufferlines = 0
    if g:lsp_preview_max_width > 0
      let l:maxwidth = min([g:lsp_preview_max_width, l:maxwidth])

      " Determine, for each line, how many "virtual" lines it spans, and add
      " these together for all lines in the buffer
      for l:line in getbufline(l:buffer, 1, '$')
        let l:num_lines = str2nr(string(ceil(strdisplaywidth(l:line) * 1.0 / g:lsp_preview_max_width)))
        let l:bufferlines += max([l:num_lines, 1])
      endfor
    else
      if s:use_vim_popup
        let l:bufferlines = line('$', a:winid)
      elseif s:use_nvim_float
        let l:bufferlines = nvim_buf_line_count(winbufnr(a:winid))
      endif
    endif

    return [l:bufferlines, l:maxwidth]
endfunction

function! lsp#ui#vim#output#float_supported() abort
    return s:use_vim_popup || s:use_nvim_float
endfunction

function! lsp#ui#vim#output#preview(server, data, options) abort
    if s:is_cmdwin()
        return
    endif

    if s:winid && type(s:preview_data) ==# type(a:data)
        \ && s:preview_data ==# a:data
        \ && type(g:lsp_preview_doubletap) ==# 3
        \ && len(g:lsp_preview_doubletap) >= 1
        \ && type(g:lsp_preview_doubletap[0]) ==# 2
        \ && index(['i', 's'], mode()[0]) ==# -1
        echo ''
        return call(g:lsp_preview_doubletap[0], [])
    endif
    " Close any previously opened preview window
    call lsp#ui#vim#output#closepreview()

    let l:current_window_id = win_getid()

    let s:winid = s:open_preview(a:data)

    let s:preview_data = a:data
    let l:lines = []
    let l:syntax_lines = []
    let l:ft = lsp#ui#vim#output#append(a:data, l:lines, l:syntax_lines)

    if has_key(a:options, 'filetype')
        let l:ft = a:options['filetype']
    endif

    let l:do_conceal = g:lsp_hover_conceal
    let l:server_info = a:server !=# '' ? lsp#get_server_info(a:server) : {}
    let l:config = get(l:server_info, 'config', {})
    let l:do_conceal = get(l:config, 'hover_conceal', l:do_conceal)

    call setbufvar(winbufnr(s:winid), 'lsp_syntax_highlights', l:syntax_lines)
    call setbufvar(winbufnr(s:winid), 'lsp_do_conceal', l:do_conceal)
    call lsp#ui#vim#output#setcontent(s:winid, l:lines, l:ft)

    let [l:bufferlines, l:maxwidth] = lsp#ui#vim#output#get_size_info(s:winid)

    if s:use_preview
        " Set statusline
        if has_key(a:options, 'statusline')
            let &l:statusline = a:options['statusline']
        endif

        call s:set_cursor(l:current_window_id, a:options)
    endif

    " Go to the previous window to adjust positioning
    call win_gotoid(l:current_window_id)

    echo ''

    if s:winid && (s:use_vim_popup || s:use_nvim_float)
      if s:use_nvim_float
        " Neovim floats
        call lsp#ui#vim#output#adjust_float_placement(l:bufferlines, l:maxwidth)
        call s:set_cursor(l:current_window_id, a:options)
        call s:add_float_closing_hooks()
      elseif s:use_vim_popup
        " Vim popups
        call s:set_cursor(l:current_window_id, a:options)
      endif
      doautocmd <nomodeline> User lsp_float_opened
    endif

    if l:ft ==? 'markdown'
        call s:import_modules()
        call s:Window.do(s:winid, {->s:Markdown.apply()})
    endif

    if !g:lsp_preview_keep_focus
        " set the focus to the preview window
        call win_gotoid(s:winid)
    endif
    return ''
endfunction

function! s:escape_string_for_display(str) abort
    return substitute(substitute(a:str, '\r\n', '\n', 'g'), '\r', '\n', 'g')
endfunction

function! lsp#ui#vim#output#append(data, lines, syntax_lines) abort
    if type(a:data) == type([])
        for l:entry in a:data
            call lsp#ui#vim#output#append(l:entry, a:lines, a:syntax_lines)
        endfor

        return 'plaintext'
    elseif type(a:data) ==# type('')
        call extend(a:lines, split(s:escape_string_for_display(a:data), "\n", v:true))
        return 'markdown'
    elseif type(a:data) ==# type({}) && has_key(a:data, 'language')
        let l:new_lines = split(s:escape_string_for_display(a:data.value), '\n')

        let l:i = 1
        while l:i <= len(l:new_lines)
            call add(a:syntax_lines, { 'line': len(a:lines) + l:i, 'language': a:data.language })
            let l:i += 1
        endwhile

        call extend(a:lines, l:new_lines)
        return 'markdown'
    elseif type(a:data) ==# type({}) && has_key(a:data, 'kind')
        if a:data.kind ==? 'markdown'
            call s:import_modules()
            let l:detail = s:MarkupContent.normalize(a:data.value, {
            \     'compact': !g:lsp_preview_fixup_conceal
            \ })
            call extend(a:lines, s:Text.split_by_eol(l:detail))
        else
            call extend(a:lines, split(s:escape_string_for_display(a:data.value), '\n', v:true))
        endif
        return a:data.kind ==? 'plaintext' ? 'text' : a:data.kind
    endif
endfunction

function! s:is_cmdwin() abort
    return getcmdwintype() !=# ''
endfunction
