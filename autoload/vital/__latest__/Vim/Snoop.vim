"=============================================================================
" FILE: autoload/vital/__latest__/Vim/Snoop.vim
" AUTHOR: haya14busa
" License: MIT license
"=============================================================================
scriptencoding utf-8
let s:save_cpo = &cpo
set cpo&vim

""" Helper:

function! s:_throw(message) abort
  throw printf('vital: Snoop: %s', a:message)
endfunction

"" Capture command
function! s:_capture(command) abort
  try
    let save_verbose = &verbose
    let &verbose = 0
    redir => out
    silent execute a:command
  finally
    redir END
    let &verbose = save_verbose
  endtry
  return out
endfunction

"" Capture command and return lines
function! s:_capture_lines(command) abort
  return split(s:_capture(a:command), "\n")
endfunction

"" Return prefix for script local functions from SID
function! s:_sprefix(sid) abort
  return printf('<SNR>%s_', a:sid)
endfunction

function! s:_source(path) abort
  try
    execute ':source' a:path
  catch /^Vim\%((\a\+)\)\=:E121/
    " NOTE: workaround for `E121: Undefined variable: s:save_cpo`
    execute ':source' a:path
  endtry
endfunction

""" Main:

"" Improved scriptnames()
" @return {sid1: path1, sid2: path2, ...}
function! s:scriptnames() abort
  let sdict = {} " { sid: path }
  for line in s:_capture_lines(':scriptnames')
    let [sid, path] = split(line, '\m^\s*\d\+\zs:\s\ze')
    let sdict[str2nr(sid)] = path " str2nr(): '  1' -> 1
  endfor
  return sdict
endfunction

"" Return SID from the given path
" return -1 if the given path is not found in scriptnames()
" NOTE: it execute `:source` a given path once if the file haven't sourced yet
function! s:sid(path) abort
  " Expand
  let tp = fnamemodify(expand(a:path), ':p') " target path
  " Relative to &runtimepath
  if !filereadable(tp)
    let tp = globpath(&runtimepath, a:path)
  endif
  if !filereadable(tp)
    return s:_throw('file not found')
  endif
  let sid = s:_sid(tp, s:scriptnames())
  if sid isnot -1
    return sid
  else
    call s:_source(tp)
    return s:_sid(tp, s:scriptnames())
  endif
endfunction

" Assume `a:abspath` is absolute path
function! s:_sid(abspath, scriptnames) abort
  " Handle symbolic link here
  let tp = resolve(simplify(a:abspath)) " target path
  for sid in keys(a:scriptnames)
    " NOTE: is simplify() necessary?
    if tp is# simplify(expand(a:scriptnames[sid]))
      return str2nr(sid)
    endif
  endfor
  return -1
endfunction

"" Return a dict which contains script-local functions from given path
" `path` should be absolute path or relative to &runtimepath
" @return {funcname: funcref, funcname2: funcref2, ...}
" USAGE:
" :echo s:sfuncs('~/.vim/bundle/plugname/autoload/plugname.vim')
" " => { 'fname1': funcref1, 'fname2': funcref2, ...}
" :echo s:sfuncs('autoload/plugname.vim')
" " => { 'fname1': funcref1, 'fname2': funcref2, ...}
function! s:sfuncs(path) abort
  return s:sid2sfuncs(s:sid(a:path))
endfunction

"" Return a dict which contains script-local functions from SID
" USAGE:
" :echo s:sid2sfuncs(1)
" " => { 'fname1': funcref1, 'fname2': funcref2, ...}
" " The file whose SID is 1 may be your vimrc
" NOTE: old regexpengine has a bug which returns 0 with
" :echo "\<SNR>" =~# "\\%#=1\x80\xfdR"     | " => 0
" But it matches correctly with :h /collection
" :echo "\<SNR>" =~# "\\%#=1[\x80][\xfd]R" | " => 1
" http://lingr.com/room/vim/archives/2015/02/13#message-21261450
let s:SNR = "[\x80][\xfd]R"
function! s:sid2sfuncs(sid) abort
  let sprefix = s:_sprefix(a:sid)
  ":h :function /{pattern}
  " ->         ^________
  "    function <SNR>14_functionname(args, ...)
  let fs = s:_capture_lines(':function ' . printf("/^%s%s_", s:SNR, a:sid))
  let r = {}
  " ->         ^--------____________-
  "    function <SNR>14_functionname(args, ...)
  for fname in map(fs, "matchstr(v:val, printf('\\m^function\\s<SNR>%d_\\zs\\w\\{-}\\ze(', a:sid))")
    let r[fname] = function(sprefix . fname)
  endfor
  return r
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" __END__
" vim: expandtab softtabstop=2 shiftwidth=2 foldmethod=marker
