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

param($global)

$PSScriptRoot = [System.IO.FileInfo]::new(${__0}).directory

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

if($global -and !(is_admin)) {
    "ERROR: you need admin rights to uninstall globally"; exit 1
}

warn 'this will uninstall scoop and all the programs that have been installed with scoop!'
$yn = read-host 'are you sure? (yN)'
if($yn -notlike 'y*') { exit }

$errors = $false
function do_uninstall($app, $global) {
    $version = current_version $app $global
    $dir = versiondir $app $version $global
    $manifest = installed_manifest $app $version $global
    $install = install_info $app $version $global
    $architecture = $install.architecture

    write-output "uninstalling $(app_name $app)"
    run_uninstaller $manifest $architecture $dir
    rm_shims $manifest $global
    env_rm_path $manifest $dir $global
    env_rm $manifest $global

    $appdir = appdir $app $global
    try {
        remove-item -r -force $appdir -ea stop
    } catch {
        $errors = $true
        warn "couldn't remove '$appdir': $_.exception"
    }
}
function rm_dir($dir) {
    try {
        remove-item -r -force $dir -ea stop
    } catch {
        abort "couldn't remove '$dir': $_"
    }
}

# run uninstallation for each app if necessary, continuing if there's
# a problem deleting a directory (which is quite likely)
if($global) {
    installed_apps $true | foreach-object { # global apps
        do_uninstall $_ $true
    }
}
installed_apps $false | foreach-object { # local apps
    do_uninstall $_ $false
}

if($errors) {
    abort "not all apps could be deleted. try again or restart"
}

rm_dir $scoopdir
if($global) { rm_dir $globaldir }

remove_from_path (shimdir $false)
if($global) { remove_from_path (shimdir $true) }

success "scoop has been uninstalled"

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
