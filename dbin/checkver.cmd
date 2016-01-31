@(echo '> nul ) &::' ) | out-null; @'
@:: ## emacs -*- tab-width: 4; coding: dos; mode: powershell; indent-tabs-mode: nil; basic-offset: 2; -*- ## (jedit) :tabsize=4:mode=perl: ## (notepad++) vim: syntax=powershell : tabstop=4 : shiftwidth=2 : expandtab : smarttab : softtabstop=2 ## modeline ( see http://archive.is/djTUD @@ http://webcitation.org/66W3EhCAP )
@setlocal
@echo off

set "__ME=%~n0"

:: require PowerShell (to self-execute)
call :$path_in_pathlist _POWERSHELL_exe powershell.exe "%PATH%;%SystemRoot%\System32\WindowsPowerShell\v1.0"
if NOT DEFINED _POWERSHELL_exe (
    echo %__ME%: ERROR: script requires PowerShell [see http://support.microsoft.com/kb/968929 {to download Windows Management Framework Core [includes PowerShell 2.0]}] 1>&2
    exit /b 1
    )

:: execute self as PowerShell script [using an endlocal block to pass a clean environment]
set __ARGS=%*
( endlocal
setlocal
:: send the least interpreted/cleanest possible ARGS to PowerShell via the environment
set __ARGS=%__ARGS%
call "%_POWERSHELL_exe%" -NoProfile -ExecutionPolicy unrestricted -Command "${__0}='%~f0'; ${__ME}='%__ME%'; ${__INPUT} = @($input); ${__ARGS}=$env:__ARGS; Invoke-Expression $( [String]::Join([environment]::newline,$(Get-Content ${__0} | foreach { $_ }))+' ; exit $LASTEXITCODE' )"
:: restore needed ENV vars
set "__ME=%__ME%"
)
set "__exit_code=%ERRORLEVEL%"

( endlocal
    exit /b %__exit_code%
)
goto :EOF

::#### SUBs

::
:$path_in_pathlist ( ref_RETURN FILENAME PATHLIST )
:: NOTE: FILENAME should be a simple filename, not a directory or filename with leading diretory prefix. CMD will match these more complex paths, but TCC will not
setlocal
set "pathlist=%~3"
set "PATH=%pathlist%"
set "_RETval=%~$PATH:2"
:$path_in_pathlist_RETURN
endlocal & set %~1^=%_RETval%
goto :EOF
::

::#### SUBs.end

goto :EOF
'@ | Out-Null
#
function __MAIN {
# "__0 = '${__0}'" ## script full path
# "__ME = '${__ME}'" ## name
# "input = '"+($input -join ';')+"'" ## STDIN
# "args = '"+($args -join ';')+"'" ## ARGS
######

# checks websites for newer versions using an (optional) regular expression defined in the manifest
# use $dir to specify a manifest directory to check from, otherwise ./bucket is used
param($app, $dir)

$PSScriptRoot = [System.IO.FileInfo]::new(${__0}).directory

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\config.ps1"

if(!$dir) { $dir = "$psscriptroot\..\bucket" }
$dir = resolve-path $dir

$search = "*"
if($app) { $search = $app }

# get apps to check
$queue = @()
get-childitem $dir "$search.json" | foreach-object {
    $json = parse_json "$dir\$_"
    if($json.checkver) {
        $queue += ,@($_, $json)
    }
}

# clear any existing events
get-event | foreach-object {
    remove-event $_.sourceidentifier
}

# start all downloads
$queue | foreach-object {
    $wc = new-object net.webclient
    register-objectevent $wc downloadstringcompleted -ea stop | out-null

    $name, $json = $_

    $url = $json.checkver.url
    if(!$url) { $url = $json.homepage }

    $state = new-object psobject @{
        app = (strip_ext $name);
        url = $url;
        json = $json;
    }

    $wc.downloadstringasync($url, $state)
}

# wait for all to complete
$in_progress = $queue.length
while($in_progress -gt 0) {
    $ev = wait-event
    remove-event $ev.sourceidentifier
    $in_progress--

    $state = $ev.sourceeventargs.userstate
    $app = $state.app
    $json = $state.json
    $url = $state.url
    $expected_ver = $json.version

    $err = $ev.sourceeventargs.error
    $page = $ev.sourceeventargs.result

    $regexp = $json.checkver.re
    if(!$regexp) { $regexp = $json.checkver }

    $regexp = "(?s)$regexp"

    write-host "$app`: " -nonewline

    if($err) {
        write-host "ERROR: $err" -f darkyellow
    } else {
        if($page -match $regexp) {
            $ver = $matches[1]
            if($ver -eq $expected_ver) {
                write-host "$ver" -f darkgreen
            } else {
                write-host "$ver" -f darkred -nonewline
                write-host " (scoop version is $expected_ver)"
            }

        } else {
            write-host "couldn't match '$regexp' in $url" -f darkred
        }
    }
}

<#
write-host "checking $(strip_ext (fname $_))..." -nonewline
$expected_ver = $json.version

$url = $json.checkver.url
if(!$url) { $url = $json.homepage }

$regexp = $json.checkver.re
if(!$regexp) { $regexp = $json.checkver }

$page = $wc.downloadstring($url)

if($page -match $regexp) {
    $ver = $matches[1]
    if($ver -eq $expected_ver) {
        write-host "$ver" -f darkgreen
    } else {
        write-host "$ver" -f darkred -nonewline
        write-host " (scoop version is $expected_ver)"
    }

} else {
    write-host "couldn't match '$regexp' in $url" -f darkred
}
#>

######
}
if ( $MyInvocation.MyCommand.CommandType -ne 'Script' ) {
    # NOT via `iex(...)`
    ${__0} = "$($MyInvocation.MyCommand.Path)"
    ${__ME} = $(get-item $MyInvocation.MyCommand.Path).BaseName
    ${__ENVPIPE} = $null
    ${__INPUT} = @($input)
    ${__ARGS} = $args -replace '(\s|`|\$)','`$1'
    }
iex ( '${__INPUT} | __MAIN '+$(${__ARGS} -join ' ') )
