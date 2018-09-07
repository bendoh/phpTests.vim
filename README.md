# VIM : PHP Testing harness

A VIM8+ plugin that will invoke and capture unit test results for PHP in a window for quick development. It offers some
integration with Vdebug for quickly debugging tests without leaving your vim environment.

With this plugin, you can quickly invoke a test for a single method (`,sm`), a file (`,sf`), or a whole suite of tests
(`,st`). There is also debugging support which can be toggled on and off (`,sd`), that when enabled, will run your tests
within Xdebug.

## Installation

Use your package manager (I use pathogen) to install this package in its proper place.

For Pathogen,

```
$ cd ~/.vim/bundle
$ git clone https://github.com/bendoh/phpTests.vim.git
```

This will install the plugin as `phpTests` in a Pathogen bundle. Call `:exec pathogen#infect()` or restart vim to load
the module.

## Overview

This plugin provides a set of user functions, output syntax, and key mappings which allow the user to run PHPUnit tests
directly within their VIM environment. It supports debugging via Xdebug, which may connect to a Vdebug frontend within
vim.

Key bindings are local to php buffers only.
To run a test on a file, use the `<leader>sf` command, which will test the currently open file.

## Commands

When in a PHP test file, the following commands can be used, assuming `,` as the `<leader>` key.

* `,st` - (call `phpTests#start()`) - Start the full test suite with no arguments, or the target given by `b:phpTestsTarget` or `g:phpTestsTarget`.

* `,ss` - (call `phpTests#stop()`) - Stop tests in their tracks.

* `,sf` - (call `phpTests#testFile()`) - Start tests against the current file.

* `,sm` - (call `phpTests#testMethod()`) - Invoke tests against the closest method to the cursor, searching backwards.

* `,sa` - (call `phpTests#startAgain()`) - Run the last test that was executed.

* `,sd` - (call `phpTests#toggleDebugging()`) - Toggle debugging mode.

## Configuration

* `g:phpTestsTarget` (default `''`) - The default test target, used when a method or file is not specified. Can be
  overridden on a per-buffer basis by setting `b:phpTestsTarget`.

* `g:phpTestsEnvironmentVars` (default `''`) - Any environment variables to inject into test runner invocation.

* `g:phpTestsCommandLeader` (default `'<leader>'`) - The leader key or sequence for prefixing test commands.

* `g:phpTestsPHPUnit` (default `'/usr/local/bin/phpunit'`) - The path to PHPUnit.

* `g:phpTestsInterpreter` (default `'/usr/bin/php'`) - The path to the interpreter invoked, including any command line options.

* `g:phpTestsOutputFormat` (default `'--teamcity'`) - The flag to specify to PHPUnit what output format it uses. Only Teamcity is currently understood by this plugin. Other settings will cause output to be unformatted.

### Remote testing settings

* `g:phpTestsSSH` (default `''`) - The SSH command used to connect to the host  which handles the tests. Leave empty for local tests.

* `g:phpTestsLocalRoot` (default `''`) - When using remote testing, the local path to the PHP root.

* `g:phpTestsRemoteRoot` (default `''`) - When using remote testing, the remote path of the PHP root.

### Debugging settings

* `g:phpTestsDebug` (default `0`) - Whether or not debug mode is enabled. Set this to `1` in your `.vimrc` to enable test
  debugging by default.

* `g:phpTestsDebugSSH` (default `g:phpTestsSSH . ' -R 9000:localhost:9000'`) - The SSH command used when debugging tests.

* `g:phpTestsDebugEnvironment` (default `'XDEBUG_CONFIG="IDEKEY=vim remote_host=localhost"'`) - Any environment
  variables added when in debugging mode.

* `g:phpTestsDebugCommand` (default `'VdebugStart'`) - The vim command used to start the debugging frontend. This can be
  used to configure a different debugging frontend.

## Customization

You can change the leader key by setting `g:phpTestsCommandLeader` in your `.vimrc`, which defines the prefix for all
the default commands.  The default key bindings can be disabled entirely by specifying `g:phpTestsCommandLeader = ''`

You can configure your own key bindings against the methods listed under "Commands" instead.

## Remote Testing

This plugin allows the user to invoke tests on a remote machine over SSH. This can be configured by setting the
the `g:phpTestsSSH` (and `g:phpTestsDebugSSH`) variables to the SSH commands used to connect to the remote machine. This
plugin assumes that there is a keypair set up for authentication, as an interactive password prompt would fail.

When doing remote testing, it is assumed that there is a tree on the remote host that corresponds to the local PHP tree
root. This can be specified using the `g:phpTestsLocalRoot` and `g:phpTestsRemoteRoot` variables, which provides a
mapping between remote and local paths and is used when invoking test on the remote machine for files specified on the
local machine.

## Test Debugging

You can toggle debugging mode using the `phpTests#toggleDebugging()` function (bound by default to `<leader>sd`). When
debugging mode is enabled, the environment variables in `g:phpTestsDebugEnvironment` are added to the invocation of the
test interpreter.

When doing debugging on a remote machine, the `g:phpTestsDebugSSH` setting is used to add any options to the SSH
command. The default value provides the option `-R 9000:localhost:9000` to SSH, which configures a port forward from the
remote machine on port 9000 to the local machine on the same port, which is the default port that most Xdebug frontends
will listen.

When a test is started in debugging mode, the test runner is started and then command specified in
`g:phpTestsDebugCommand` is immediately executed (if defined.) Generally, this means you can just type `,sf` and the
test will start on the current file, and break at the first line.

## Questions?

Please feel free to submit an issue or submit a Pull Request!
