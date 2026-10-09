if exists('*gettagstack') && exists('*settagstack')
    function! lsp#utils#tagstack#_update() abort
        let l:bufnr = bufnr('%')
        let l:item = {'bufnr': l:bufnr, 'from': [l:bufnr, line('.'), col('.'), 0], 'tagname': expand('<cword>')}
        let l:winid = win_getid()

        let l:stack = gettagstack(l:winid)
        if l:stack['length'] == l:stack['curidx']
            " Replace the last items with item.
            let l:action = 'r'
            let l:stack['items'][l:stack['curidx']-1] = l:item
        elseif l:stack['length'] > l:stack['curidx']
            " Replace items after used items with item.
            let l:action = 'r'
            if l:stack['curidx'] > 1
                let l:stack['items'] = add(l:stack['items'][:l:stack['curidx']-2], l:item)
            else
                let l:stack['items'] = [l:item]
            endif
        else
            " Append item.
            let l:action = 'a'
            let l:stack['items'] = [l:item]
        endif
        let l:stack['curidx'] += 1

        call settagstack(l:winid, l:stack, l:action)
    endfunction
else
    function! lsp#utils#tagstack#_update() abort
        " do nothing
    endfunction
endif

if exists('*gettagstack') && exists('*settagstack')
    " Record that a qf list was produced; the tagstack entry is deferred
    " until the user actually selects an item.
    function! lsp#utils#tagstack#_defer(qfid, tagname) abort
        let s:pending = {
            \ 'qfid': a:qfid,
            \ 'winid': win_getid(),
            \ 'tagname': a:tagname,
            \ 'base': v:null,
            \ }
    endfunction

    function! lsp#utils#tagstack#_commit() abort
        if !exists('s:pending') || s:pending is v:null
            return
        endif
        let l:p = s:pending
        if getqflist({'id': 0})['id'] !=# l:p['qfid']
            return
        endif
        if !win_id2win(l:p['winid'])
            return
        endif

        let l:stack = gettagstack(l:p['winid'])
        if l:p['base'] is v:null
            " First selection from this list: remember the stack without us.
            let l:p['base'] = l:stack['curidx'] > 1
                \ ? l:stack['items'][0 : l:stack['curidx'] - 2]
                \ : []
        endif

        " Read the cursor from the window we are jumping *from*, not the qf window.
        let l:pos = []
        let g:lsp_tagstack_tmp_pos = []
        call win_execute(l:p['winid'],
            \ 'let g:lsp_tagstack_tmp_pos = [bufnr("%"), line("."), col("."), 0]')
        let l:pos = g:lsp_tagstack_tmp_pos
        unlet g:lsp_tagstack_tmp_pos
        if empty(l:pos)
            return
        endif

        let l:items = copy(l:p['base']) + [{
            \ 'bufnr': l:pos[0],
            \ 'from': l:pos,
            \ 'tagname': l:p['tagname'],
            \ 'matchnr': 1,
            \ }]
        call settagstack(l:p['winid'],
            \ {'items': l:items, 'curidx': len(l:items) + 1}, 'r')
    endfunction
else
    function! lsp#utils#tagstack#_defer(qfid, tagname) abort
    endfunction
    function! lsp#utils#tagstack#_commit() abort
    endfunction
endif
