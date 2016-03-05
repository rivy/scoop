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

$rule_exclusions = @( 'PSAvoidUsingWriteHost' )

##

# $repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent
$repo_dir = [System.IO.FileInfo]::new(${__0}).directory.parent

$repo_files = @( Get-ChildItem $repo_dir.fullname -file -recurse -force )

$project_file_exclusions = @(
    $([regex]::Escape($repo_dir.fullname)+'\\.git\\.*$')
    $([regex]::Escape($repo_dir.fullname)+'\\vendor\\.*$')
)

$files = @(
    $repo_files |
        where-object { $_.fullname -inotmatch $($project_file_exclusions -join '|') } |
        where-object { $_.fullname -imatch '.(ps1|psm1)$' }
)

$files_exist = ($files.Count -gt 0)

if (-not $files_exist) { throw "no files found to critique"}

$lint_module_name = 'PSScriptAnalyzer'
$lint_module_version = '1.3.0'
if (-not (Get-Module $lint_module_name)) {
    $filename = [System.IO.Path]::Combine($repo_dir.fullname,"vendor\$lint_module_name\$lint_module_version\$lint_module_name.psd1")
    import-module $(resolve-path $filename)
}
$have_delinter = Get-Module $lint_module_name

if (-not $have_delinter) { throw "unable to find/load '$lint_module_name' for critique"}

function abbrev_message {
    param([string]$message,[int]$size=$host.ui.RawUI.windowsize.width-1)
    $result = $message
    $continuation = '...'
    $continuation_size = $continuation.length
    if ($message.length -gt $size) { $result = $message.substring(0, $size-$continuation_size) + $continuation }
    $result
}

if ($null -ne $files) { foreach ($file in $files) {
    $repo_relative_name = [System.IO.Path]::Combine(($file.directoryname -replace $('^'+[regex]::escape($repo_dir.fullname)),'.'), $file.name)
    write-host -nonewline "Analyzing $repo_relative_name ... "
    $notes = Invoke-ScriptAnalyzer $file.FullName -excluderule $rule_exclusions
    if ($notes.count -ne 0) {
        write-output ''
        foreach ($note in $notes) {
            if ($note.severity -eq 'information') { write-host -fore cyan $(abbrev_message $("info:(@$($note.line)):'$($note.rulename)': $($note.message)")) }
            if ($note.severity -eq 'warning') { write-host -fore darkyellow $(abbrev_message $("warn:(@$($note.line)):'$($note.rulename)': $($note.message)")) }
            if ($note.severity -eq 'error') { write-host -fore red $(abbrev_message $("err!:(@$($note.line)):'$($note.rulename)': $($note.message)")) }
        }
    } else { write-host -fore green "done" }
}}

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
