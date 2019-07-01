""
" PHP (and likely other language) test invoker and output munger
" for VIM 8.
"
" Author: Benjamin Doherty <bendoh@github>
"/
if v:version < 800
  finish
endif

if !exists('g:phpTestsOptions') 
  let g:phpTestsOptions = {
      \ 'CommandLeader': '<leader>' ,
      \ 'Interpreter': '/usr/bin/php' ,
      \ 'PHPUnit': '/usr/local/bin/phpunit' ,
      \ 'Target': '' ,
      \ 'Environment': '',
      \ 'OutputFormat': '--teamcity',
      \ 'Shell': '',
      \ 'LocalRoot': '',
      \ 'RemoteRoot': '',
      \ 'DebugShell': '',
      \ 'DebugEnvironment': 'XDEBUG_CONFIG="IDEKEY=vim remote_host=localhost"',
      \ 'DebugCommand': 'VdebugStart',
      \ 'Debug': 0
      \ }
endif

let s:outputLineContinue = '> '

let g:testOutputBufferName = 'TestOutput'

function! phpTests#toggleDebugging()
  let g:phpTestsOptions['Debug'] = !g:phpTestsOptions['Debug']
  echo 'phpTests: PHP test debugging is ' . (g:phpTestsOptions['Debug'] ? 'enabled' : 'disabled')
endfunction

function! phpTests#open()
  if !bufexists(g:testOutputBufferName)
    badd TestOutput
  endif

  if bufwinnr(g:testOutputBufferName) == -1
    sb! +wincmd\ J|res\ 10 TestOutput
    normal G
  endif
endfunction

" Append output line(s) as a block
function! phpTests#addOutput(out)
  let l:lines = split(phpTests#chomp(a:out), '|n', 1)

  call appendbufline(g:testOutputBufferName, '$', repeat(' ', s:indent * 3) . l:lines[0])

  for l:nextLine in l:lines[1:]
    call appendbufline(g:testOutputBufferName, '$', repeat(' ', s:indent * 3) . s:outputLineContinue . l:nextLine)
  endfor

  " Keep scrolling to the bottom
  call phpTests#scroll()
endfunction

function! phpTests#scroll()
  let l:thiswinnr = bufwinnr('%')
  let l:winnr = bufwinnr(g:testOutputBufferName)
  
  exec l:winnr . 'windo normal G'
  if l:winnr != l:thiswinnr
    winc p
  endif

endfunction

" Add a line and mark it as the last line
function! phpTests#addLine(out)
  let s:lastLine = a:out
  call appendbufline(g:testOutputBufferName, '$', repeat(' ', s:indent * 3) . s:lastLine)

  call phpTests#scroll()
endfunction

function! phpTests#replaceLine(line)
  call deletebufline(g:testOutputBufferName, '$', '$')
  call phpTests#addLine(a:line)
endfunction

function! phpTests#appendLine(out)
  call phpTests#replaceLine(s:lastLine . a:out)
endfunction

function! phpTests#updateLineStatus(line)
  call phpTests#replaceLine(substitute(s:lastLine, '^...', a:line, ''))
endfunction

function! phpTests#chomp(line)
  return substitute(a:line, '\s*\n\*$', '', '')
endfunction

function! phpTests#trim(line)
  return substitute(phpTests#chomp(a:line), '^\s*', '', '')
endfunction

function! phpTests#addDiff(expected, actual)
  let eLines = split(phpTests#chomp(a:expected), '|n', 1)
  let aLines = split(phpTests#chomp(a:actual), '|n', 1)

  let eTemp = tempname()
  let aTemp = tempname()

  call writefile(eLines, eTemp)
  call writefile(aLines, aTemp)

  silent let result = systemlist(join(['diff -au', eTemp, aTemp]))[2:]

  let s:outputLineContinue = '| '
  call phpTests#addOutput(join(result, '|n'))
  let s:outputLineContinue = '> '
  silent call system('!rm ' . eTemp . ' ' . aTemp)
endfunction

function! phpTests#handleOutput(channel, line)
  " Chomp out any trailing whitespace
  let l:line = phpTests#chomp(a:line)

  " Ignore empty lines
  if l:line == ''
    return
  endif

  " Attempt to parse out terminal color escape sequences
  let l:matches = matchlist(l:line, '^\s*\e[\(\d\+\|\d\+;\d\+\)m')
  let l:colors = []

  while !empty(l:matches)
    let l:colors += [l:matches[1]]
    let l:line = strpart(l:line, len(l:matches[0]))
    let l:matches = matchlist(l:line, '^\e[\(\d\+\|\d\+;\d\+\)m')
  endwhile

  if !empty(l:colors)
    let l:line = '***' . l:line
  endif

  let idx = stridx(l:line, '##teamcity[')

  " Emit any non-teamcity lines
  if l:idx == -1
    call phpTests#addOutput(l:line)
    return
  endif

  " Parse teamcity event and properties
  let l:content = strpart(a:line, idx + strlen('##teamcity['))
  let l:content = strpart(l:content, 0, strlen(l:content)-1)

  let l:eventMatch = matchlist(l:content, '^\(\w\+\)\>')

  if l:eventMatch != []
    let l:event = l:eventMatch[1]
  else
    let l:event = ''
  endif

  let l:props = {}

  for l:prop in ['name', 'locationHint', 'duration', 'flowId', 'count', 'type', 'actual', 'expected', 'details', 'message']
    let l:matches = matchlist(l:content, '\<' . l:prop . '=''\(.\{-}\)|\@<!''')

    if l:matches != []
      let l:props[l:prop] = phpTests#chomp(l:matches[1])

      " Replace escaped characters
      for l:escapechar in ['[', ']', '''']
        let l:props[l:prop] = substitute(l:props[l:prop], '|' . l:escapechar, l:escapechar, 'g')
      endfor

    else
      let l:props[l:prop] = ''
    endif
  endfor

  if l:event == 'testCount'
    call phpTests#addLine('=== Running ' . l:props.count . ' tests')
  elseif l:event == 'testSuiteStarted'
    call phpTests#addLine('>>> ' . l:props.name)
    let s:indent += 1
  elseif l:event == 'testStarted'
    call phpTests#addLine('... ' . l:props.name)
    let s:failure = 0
    let s:ignored = 0
  elseif l:event == 'testFailed'
    " Mark the line with !!! on failure
    call phpTests#updateLineStatus('!!!')

    if l:props.type == 'comparisonFailure'
      call phpTests#addOutput('Message: ' . l:props.message)
      call phpTests#addDiff(l:props.expected, l:props.actual)
    elseif l:props.type == '' && l:props.message != ''
      call phpTests#addOutput('Message: ' . l:props.message)
    elseif l:props.type != ''
      call phpTests#appendLine(' (' . l:props.type . ')')
    endif

    let s:failure = 1
  elseif l:event == 'testFinished'
    if s:ignored == 1
      return
    endif

    " Mark the line with +++ on success
    if s:failure == 0
      call phpTests#updateLineStatus('+++')
    endif

    call phpTests#appendLine('   ' . l:props.duration . 'ms')
  elseif l:event == 'testSuiteFinished'
    let s:indent -= 1
  elseif l:event == 'testIgnored'
    call phpTests#updateLineStatus('~~~')
    call phpTests#addOutput('~ Reason: ' . l:props.message)

    let s:ignored = 1
  elseif l:event != ''
    call phpTests#addOutput('Unknown event: ' . l:event . ' props: ' . string(l:props) . ' ' . a:line)
  endif

  if l:props.details != ''
    call phpTests#addOutput('Details:|n' . substitute(l:props.details, g:phpTestsOptions['RemoteRoot'], '', 'g'))
  endif
endfunction

function! phpTests#handleError(channel, err)
  call phpTests#addLine('Error: ' . a:err)
endfunction

function! phpTests#handleExit(channel, code)
  let s:exitCode = a:code
  unlet! s:testJob
  redraws!
endfunction

function! phpTests#handleClose(channel)
  call phpTests#addLine(s:exitCode == 0 ? 'Done, no errors' : ('Done, exit code ' . s:exitCode))
endfunction

" Test the closest method matching test_
function! phpTests#testMethod()
  if &filetype != "php"
    return
  endif

  " save the cursor position to restore at the end
  let l:cursorPos = getpos('.')

  " figure out mapped remote file path
  let l:mapped = substitute(expand('%:p'), g:phpTestsOptions['LocalRoot'], g:phpTestsOptions['RemoteRoot'], '')

  " search backwards for the containing method from the end of the current
  " line
  call cursor(l:cursorPos[1]+1, 0)
  let l:methodLine = search('function\s\+\(\w\+\)\>', 'ncbW')

  if l:methodLine > 0
    let l:matches = matchlist(getline(l:methodLine), 'function\s\+\(\w\+\)\>')

    if l:matches != [] && match(l:matches[1], 'test') == 0
      call phpTests#startFiltered('--filter ''/::' . l:matches[1] . '.*/'' ' . l:mapped)
    else
      echo 'Method "' . l:matches[1] . '" is not a test method'
    endif
  else
      echo 'No testing method found'
  endif

  " restore the cursor
  call cursor(l:cursorPos[1], l:cursorPos[2])
endfunction

" Test the file
function! phpTests#testFile()
  if &filetype != "php"
    return
  endif

  " search backwards for the containing method
  let mapped = substitute(expand('%:p'), g:phpTestsOptions['LocalRoot'], g:phpTestsOptions['RemoteRoot'], '')

  call phpTests#startFiltered(l:mapped)
endfunction

" Status line
function! phpTests#status()
  if exists('s:testJob')
    return 'Running...'
  else
    return ''
  endif
endfunction

function! phpTests#initBuffer()
  if &filetype == 'php'
    " Mappings that only apply in PHP buffers
    exec 'nnoremap <buffer> <silent> ' . g:phpTestsOptions['CommandLeader'] . 'sm :call phpTests#testMethod()<CR>'
    exec 'nnoremap <buffer> <silent> ' . g:phpTestsOptions['CommandLeader'] . 'sf :call phpTests#testFile()<CR>'
  endif
endfunction

function! phpTests#initOutput()
  setlocal buftype=nofile syntax=php_test_output wrap norelativenumber nonumber textwidth=0 colorcolumn= noswapfile
  noremap <silent> <buffer> <C-c> :silent call phpTests#stop()<CR>
endfunction

function! phpTests#bindKeys()
  " Global mappings
  exec 'nnoremap <silent> ' . g:phpTestsOptions['CommandLeader'] . 'st :call phpTests#start()<CR>'
  exec 'nnoremap <silent> ' . g:phpTestsOptions['CommandLeader'] . 'sa :call phpTests#startAgain()<CR>'
  exec 'nnoremap <silent> ' . g:phpTestsOptions['CommandLeader'] . 'ss :call phpTests#stop()<CR>'
  exec 'nnoremap <silent> ' . g:phpTestsOptions['CommandLeader'] . 'sd :call phpTests#toggleDebugging()<CR>'
endfunction

augroup PhpTests
  au!
  au BufRead,BufNew * call phpTests#initBuffer()
  au BufEnter TestOutput call phpTests#initOutput()
augroup END

" There HAS to be a better way to do this) == 1
" Munge arguments like `foo "bar with" spaces` into a list like
" ['foo', 'bar with', 'spaces']
function! phpTests#splitQuotes(str)
  let l:item = ''
  let l:escape = 0
  let l:inQuote = ''
  let l:items = []

  " Basic string parsing state machine
  for l:i in range(0, strlen(a:str) - 1)
    let l:char = a:str[l:i]

    " Pull in escaped characters literally
    if l:escape == 1
      let l:item .= l:char
      let l:escape = 0
      continue
    endif

    if l:char == '\\'
      let l:escape = 1
      continue
    endif

    if l:inQuote != ''
      " We're in a quote
      if l:char != l:inQuote
        let l:item .= l:char
      else
        " But this is the closing quote, so add the item
        let l:inQuote = ''
        call add(l:items, l:item)
        let l:item = ''
      endif

      continue
    elseif l:char =~ '\s'
      if l:item != ''
        call add(l:items, l:item)
        let l:item = ''
      endif

      continue
    endif
    
    if a:str[l:i] == '"' || a:str[l:i] == "'"
      let l:inQuote = a:str[l:i]
      continue
    endif

    let l:item .= l:char
  endfor

  if l:inQuote != ''
    throw 'Unmatched quote `' . l:inQuote . '` in given string'
  endif

  if l:item != ''
    call add(l:items, l:item)
  endif
    
  return l:items
endfunction

function! phpTests#option(q_args)
  let l:options = phpTests#splitQuotes(a:q_args)

  if len(l:options) == 1
    if has_key(g:phpTestsOptions, l:options[0])
      echo 'PHP Test option ' . l:options[0] . ': ' . g:phpTestsOptions[l:options[0]]
      return
    else
      echoerr 'No PHP test option "' . l:options[0] . '"'
    endif
    return
  endif
    
  for l:i in range(0, float2nr(len(l:options) / 2) - 1)
    let l:option = l:options[l:i]
    let l:value = l:options[l:i + 1]

    if has_key(g:phpTestsOptions, l:option)
      let g:phpTestsOptions[l:option] = l:value
    else
      echoerr 'No PHP test option "' . l:option . '" to set'
    endif
  endfor

  if len(l:options) % 2 == 1
    call phpTests#option(l:options[-1])
  endif
endfunction

function! phpTests#optionList(argLead, cmd, P)
  let l:matches = []
  " If we already have a word, no more
  if match(a:cmd, '^PhpTestOption \w\+ ') == 0
    return []
  endif

  for l:key in keys(g:phpTestsOptions)
    if a:argLead == strpart(l:key, 0, strlen(a:argLead))
      call add(l:matches, l:key)
    endif
  endfor

  return l:matches
endfunction

command! -nargs=+ -complete=customlist,phpTests#optionList PhpTestOption call phpTests#option(<q-args>)

function! phpTests#getOption(option)
  return g:phpTestsOptions[option]
endfunction 

function! phpTests#startFiltered(filter)
  if exists('s:testJob')
    echo "Already running a test in the background"
    return
  endif

  let s:lastTestFilter = a:filter

  let l:opt = g:phpTestsOptions
  if l:opt['Debug']
    let l:environment = l:opt['DebugEnvironment'] . ' ' . l:opt['Environment']
  else
    let l:environment = l:opt['Environment']
  endif

  if l:opt['DebugShell'] && l:opt['Debug']
    let l:shell = l:opt['DebugShell']
  elseif g:phpTestsOptions['Shell'] != ''
    let l:shell = l:opt['Shell']
  else
    let l:shell = ''
  endif

  let l:command = l:shell . ' ' . l:environment . ' ' . g:phpTestsOptions['Interpreter'] . ' ' . g:phpTestsOptions['PHPUnit'] . ' ' . g:phpTestsOptions['OutputFormat'] . ' ' . a:filter
  let s:indent = 0

  " Open a 10 line window and move it to the bottom
  call phpTests#open()
  call phpTests#addOutput('shell=' . l:shell)
  call phpTests#addOutput('')
  call phpTests#addOutput('Starting tests [' . a:filter . ']')
  call phpTests#addLine("$ " . l:command)

  let s:exitCode = 0
  let s:testJob = job_start(l:command, {
        \ 'in_io': 'null',
        \ 'out_cb': 'phpTests#handleOutput',
        \ 'err_cb': 'phpTests#handleError',
        \ 'exit_cb': 'phpTests#handleExit',
        \ 'close_cb': 'phpTests#handleClose'
  \ })

  if g:phpTestsOptions['Debug'] && g:phpTestsOptions['DebugCommand'] != ''
    exec g:phpTestsOptions['DebugCommand']
  endif

endfunction

function! phpTests#startAgain()
  if s:lastTestFilter == ''
    echo 'No test  to start again!'
    return
  endif

  call phpTests#startFiltered(s:lastTestFilter)
endfunction

function! phpTests#start()
  if exists('b:phpTestsTarget')
    let target = b:phpTestsTarget
  else
    let target = g:phpTestsOptions['Target']
  endif

  call phpTests#startFiltered(l:target)
endfunction

function! phpTests#stop()
  if exists('s:testJob')
    call job_stop(s:testJob)
  endif
  unlet! s:testJob
  python3 debugger and debugger.close()
endfunction
