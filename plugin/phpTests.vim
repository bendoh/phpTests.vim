" Make sure we're running VIM version 8 or higher.
if v:version < 800
  throw 'Sorry, the phpTests plugin requires VIM version 8 or higher'
endif

if !exists('g:phpTestsPHPUnit') | let g:phpTestsPHPUnit = '/usr/local/bin/phpunit' | endif
if !exists('g:phpTestsInterpreter') | let g:phpTestsInterpreter = '/usr/bin/php' | endif
if !exists('g:phpTestsDebug') | let g:phpTestsDebug = 0 | endif
if !exists('g:phpTestsEnvironmentVars') | let g:phpTestsEnvironmentVars = '' | endif
if !exists('g:phpTestsDebugEnvironment') | let g:phpTestsDebugEnvironment = 'XDEBUG_CONFIG="IDEKEY=vim remote_host=localhost"' | endif
if !exists('g:phpTestsDebugCommand') | let g:phpTestsDebugCommand = 'VdebugStart' | endif
if !exists('g:phpTestsLastFilter') | let g:phpTestsLastFilter = '' | endif
if !exists('g:phpTestsOutputFormat') | let g:phpTestsOutputFormat='--teamcity' | endif
if !exists('g:phpTestsSSH') | let g:phpTestsSSH='' | endif
if !exists('g:phpTestsDebugSSH') | let g:phpTestsDebugSSH=g:phpTestsSSH . ' -R 9000:localhost:9000' | endif

if !exists('g:phpTestsLocalRoot') | let g:phpTestsLocalRoot='' | endif
if !exists('g:phpTestsRemoteRoot') | let g:phpTestsRemoteRoot='' | endif
if !exists('g:phpTestsTarget') | let g:phpTestsRemoteRoot='' | endif

" Did we enter the output window automatically, or intentionally?
if !exists('s:autoEntered') | let s:autoEntered = 0 | endif

function! phpTests#toggleDebugging()
  let g:phpTestsDebug = !g:phpTestsDebug 
  echo 'phpTests: PHP test debugging is ' . (g:phpTestsDebug ? 'enabled' : 'disabled')
endfunction

" Set a flag to indicate whether or not we clicked into the output buffer
" or if we were programatically taken there. Use this to determine if we
" stay in the window or not
function! phpTests#setEnterFlag()
  if s:autoEntered == 0
    let s:prevBufWinNR = winnr()
  endif
endfunction

function! phpTests#open()
  badd TestOutput
  
  if bufwinnr('%') != bufwinnr('TestOutput')
    let s:prevBufWinNR = bufwinnr('%')
  endif

  if bufwinnr('TestOutput') == -1
    sb! +wincmd\ J|res\ 10 TestOutput
    normal G
  endif

  let s:autoEntered = 1

  exec bufwinnr('TestOutput') . 'wincmd w'
endfunction

function! phpTests#return()
  if s:prevBufWinNR != bufwinnr('TestOutput')
    wincmd p
  endif
  let s:autoEntered = 0
endfunction

" Append a output line but don't track it as the last line
function! phpTests#addOutput(out)
  call phpTests#open()
  let l:lines = split(phpTests#chomp(a:out), '|n', 1)

  call append('$', repeat(' ', s:indent * 3) . l:lines[0])

  for l:nextLine in l:lines[1:]
    if l:nextLine != ' '
      call append('$', repeat(' ', s:indent * 3) . '> ' . l:nextLine)
    endif
      
  endfor

  normal G

  call phpTests#return()
endfunction

" Add a line and mark it as the last line
function! phpTests#addLine(out)
  call phpTests#open()

  call append('$', repeat(' ', s:indent * 3) . a:out)
  normal G
  let s:lastLineAppended = getcurpos()[1]

  call phpTests#return()
endfunction

function! phpTests#appendLine(out)
  call phpTests#open()

  exec s:lastLineAppended
  normal $
  exec 'normal a' . a:out
  
  call phpTests#return()
endfunction

function! phpTests#updateLineStatus(line)
  call phpTests#open()
  exec s:lastLineAppended
  normal 0
  exec 'normal ' . (s:indent * 3) . 'l'
  exec 'normal R' . a:line
  call phpTests#return()
endfunction

function! phpTests#chomp(line)
  return substitute(a:line, '\s*\n\+$', '', '')
endfunction

function! phpTests#trim(line)
  return substitute(phpTests#chomp(a:line), '^\s*', '', '')
endfunction

function! phpTests#addDiff(expected, actual)
  let eLines = split(phpTests#chomp(a:expected), '|n', 1)
  let aLines = split(phpTests#chomp(a:actual), '|n', 1)

  let eTemp = tempname()
  let aTemp = tempname()
  let oTemp = tempname()

  echo eLines
  echo aLines

  call writefile(eLines, eTemp)
  call writefile(aLines, aTemp)

  silent execute join(['!diff -au', eTemp, aTemp, '>' . oTemp])

  silent let result = readfile(oTemp)[2:]

  let result = map
  call phpTests#addOutput('- Expected')
  call phpTests#addOutput('+ Actual')

  call phpTests#addOutput(join(result, '|n'))
  silent execute join(['!rm', eTemp, aTemp, oTemp])
  redraw!
endfunction

function! phpTests#handleOutput(channel, line)
  " Chomp out any trailing whitespace
  let l:line = phpTests#chomp(a:line)
  let idx = stridx(l:line, '##teamcity[')

  " Ignore empty lines
  if l:line == ''
    return
  endif

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
      let l:props[l:prop] = l:matches[1]

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
    call phpTests#appendLine('   reason: ' . l:props.message)

    let s:ignored = 1
  elseif l:event != ''
    call phpTests#addOutput('Unknown event: ' . l:event . ' props: ' . string(l:props) . ' ' . a:line)
  endif

  if l:props.details != ''
    call phpTests#addOutput('Details:|n' . substitute(l:props.details, g:phpTestsRemoteRoot, '', 'g'))
  endif
endfunction

function! phpTests#handleError(channel, err)
  call phpTests#addLine('Error: ' . a:err)
endfunction

function! phpTests#handleExit(channel, code)
  unlet s:testJob
  let s:exitCode = a:code
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
  let l:mapped = substitute(expand('%:p'), g:phpTestsLocalRoot, g:phpTestsRemoteRoot, '')
  
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
  let mapped = substitute(expand('%:p'), g:phpTestsLocalRoot, g:phpTestsRemoteRoot, '')

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

augroup PhpTests
  au!
  au BufEnter TestOutput setlocal buftype=nofile syntax=php_test_output wrap norelativenumber nonumber textwidth=0 colorcolumn= | call phpTests#setEnterFlag() | noremap <silent> <buffer> <C-c> :silent call phpTests#stop()<CR>
augroup END

function! phpTests#startFiltered(filter)
  if exists('s:testJob')
    echo "Already running a test in the background"
    return
  endif

  let g:phpTestsLastFilter = a:filter
  let l:environmentVars = (g:phpTestsDebug ? (g:phpTestsDebugEnvironment . ' ') : '') . g:phpTestsEnvironmentVars

  if g:phpTestsSSH != ''
    let l:ssh = (g:phpTestsDebug ? g:phpTestsDebugSSH : g:phpTestsSSH) . ' '
  else
    let l:ssh = ''
  endif

  let l:command = l:ssh . l:environmentVars . " " . g:phpTestsInterpreter . " " . g:phpTestsPHPUnit . " " . g:phpTestsOutputFormat . " " . a:filter
  let s:indent = 0

  " Open a 10 line window and move it to the bottom
  call phpTests#open()
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

  if g:phpTestsDebug && g:phpTestsDebugCommand != ''
    exec g:phpTestsDebugCommand
  endif

endfunction

function! phpTests#startAgain()
  if g:phpTestsLastFilter == ''
    return
  endif

  call phpTests#startFiltered(g:phpTestsLastFilter)
endfunction

function! phpTests#start()
  if exists('b:phpTestsTarget')
    let target = b:phpTestsTarget
  else
    let target = g:phpTestsTarget
  endif

  call phpTests#startFiltered(l:target)
endfunction

function! phpTests#stop()
  if exists('s:testJob')
    call job_stop(s:testJob)
  endif
endfunction 
