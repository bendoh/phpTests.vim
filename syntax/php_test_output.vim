" PHP Tests output

syn match phpTestCommand /^> /
syn match phpTestComplete /^Tests complete/
syn region phpTestErrorMessage matchgroup=phpTestError start=/^Error:/ end=/$/ 
syn region phpTestGroup matchgroup=phpTestGroupMarker start=/>>>/ end=/$/ 
syn region phpTestFailureInfo matchgroup=phpTestFailure start=/!!!/ end=/$/ contains=phpTestTime
syn region phpTestSuccessMethod matchgroup=phpTestSuccess start=/+++/ end=/$/ contains=phpTestTime
syn match phpTestTime /\d\+\zems/ contained
syn match phpTestPending /^\.\.\./
syn match phpTestFailures /^FAILURES!/
syn match phpTestExpected /| - .*/
syn match phpTestActual /| + .*/

hi link phpTestExpected DiffDelete
hi link phpTestActual DiffAdd
hi link phpTestCommand Identifier
hi link phpTestError Debug
hi link phpTestPending Comment
hi link phpTestSuccess Type
hi link phpTestSuccessMessage Type
hi link phpTestComplete Type
hi link phpTestErrorMessage String
hi link phpTestGroupMarker String
hi link phpTestGroup Label
hi link phpTestFailures Underlined
hi link phpTestFailure Error
hi link phpTestTime Statement
