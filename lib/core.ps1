$scoopdir = $env:SCOOP, "$env:LOCALAPPDATA\scoop" | select-object -first 1
$globaldir = $env:SCOOP_GLOBAL, "$($env:programdata.tolower())\scoop" | select-object -first 1

# projectrootpath will remain $null when core.ps1 is included via the "locationless" initial install script
$projectrootpath = $null
if ($MyInvocation.MyCommand.Path) { $projectrootpath = $($MyInvocation.MyCommand.Path | Split-Path | Split-Path) }

$CMDenvpipe = $env:SCOOP__CMDenvpipe

# defaults
$default = @{}
#
$default['repo.domain'] = 'github.com'
$default['repo.owner'] = 'rivy'
$default['repo.name'] = 'scoop'
$default['repo.branch'] = 'tr-wip'
$default['repo'] = "https://$($default['repo.domain'])/$($default['repo.owner'])/$($default['repo.name'])"
$default['repo.download.base'] = 'cdn.statically.io/gh'

# helper functions
function coalesce($a, $b) { if($a) { $a } else { $b } }
function format($str, $hash) {
    $hash.keys | foreach-object { set-variable $_ $hash[$_] }
    $executionContext.invokeCommand.expandString($str)
}
function is_admin {
    $admin = [security.principal.windowsbuiltinrole]::administrator
    $id = [security.principal.windowsidentity]::getcurrent()
    ([security.principal.windowsprincipal]($id)).isinrole($admin)
}

# messages
function error($msg) { write-host "ERR!: $msg" -f darkred }
function warn($msg) { write-host "WARN: $msg" -f darkyellow }
function info($msg) { write-host $msg -f darkcyan }
function success($msg) { write-host $msg -f darkgreen }
function trace($msg) { write-host "TRACE: $msg" -f darkmagenta }

# abort
function abort($msg, $exit_code=-1) { error $msg; exit $exit_code }


# dirs
function cachedir() { "$scoopdir\cache" } # always local
function basedir($global) { if($global) { $globaldir } else { $scoopdir } }
function appsdir($global) { "$(basedir $global)\apps" }
function shimdir($global) { "$(basedir $global)\shims" }
function appdir($app, $global) { "$(appsdir $global)\$(app_name $app)" }
function versiondir($app, $version, $global) { "$(appdir $app $global)\$version" }

# apps
function sanitary_path($path) { [regex]::replace($path, "[/\\?:*<>|]", "") }
function installed($app, $global=$null) {
    if($null -eq $global) { (installed $app $true) -or (installed $app $false); return }
    @(versions $app $global).count -gt 0
}
function installed_apps($global) {
    $dir = appsdir $global
    if(test-path $dir) {
        $app_names = get-childitem $dir | where-object { $_.psiscontainer -and $_.name -ne 'scoop' } | foreach-object { $_.name }
        if ($null -ne $app_names) { $app_names | foreach-object {
            $app = $_
            $versions = @(versions (app $app) $global)
            if ($null -ne $versions) { $versions | foreach-object { app $app $null $_ } }
        }}
    }
}

# paths
function fname($path) { split-path $path -leaf }
function strip_ext($fname) { $fname -replace '\.[^\.]*$', '' }

function ensure($dir) { if(!(test-path $dir)) { mkdir $dir > $null }; resolve-path $dir }
function fullpath($path) { # should be ~ rooted
    $executionContext.sessionState.path.getUnresolvedProviderPathFromPSPath($path)
}
function rootrelpath($path) { join-path $projectrootpath $path } # relative to project main directory
function is_local($path) {
    ($path -notmatch '^https?://') -and (test-path $path)
}
function normalize_path($path) {
    # $path does NOT need to exist
    $path = $path -replace "^~", $env:USERPROFILE   # expand '~' for PowerShell paths
    if ($path) {
        ## ToDO: handle broken path pieces better (eg, "C:\xxx\C:\yyy" causes a fault)
        # trace "path = $path"
        $path = [System.IO.Path]::GetFullPath($path)
        }
    $path = $path.TrimEnd( [System.IO.Path]::DirectorySeparatorChar )
    $path
}
function split_pathlist($pathlist) {
    # PATHLIST == semicolon separated paths (possibly double-quoted with internal semicolons)
    # RETURN = array of normalized paths
    $regex = ';(?=(?:[^\"]*\"[^\"]*\")*(?![^\"]*\"))'   # ';' followed by zero or more balanced double-quotes
    @( $pathlist -split $regex | foreach-object { normalize_path $_ } )
}

# operations
function dl($url,$to) {
    $wc = new-object system.net.webClient
    $wc.headers.add('User-Agent', 'Scoop/1.0')
    $wc.downloadFile($url,$to)

}
function env { param($name,$value,$targetEnvironment)
    if ( $PSBoundParameters.ContainsKey('targetEnvironment') ) {
        # $targetEnvironment is expected to be $null, [bool], [string], or [System.EnvironmentVariableTarget]
        # NOTE: if $targetEnvironment is specified, either 'User' or 'System' will be selected (allows usage of $global == $null or $false for 'User')
        if ($null -eq $targetEnvironment) { $targetEnvironment = [System.EnvironmentVariableTarget]::User }
        elseif ($targetEnvironment -is [bool]) {
            # from initial usage pattern
            if ($targetEnvironment) { $targetEnvironment = [System.EnvironmentVariableTarget]::Machine }
            else { $targetEnvironment = [System.EnvironmentVariableTarget]::User }
        }
        elseif (($targetEnvironment -eq '') -or ($targetEnvironment -eq 'Process') -or ($targetEnvironment -eq 'Session')) { $targetEnvironment = [System.EnvironmentVariableTarget]::Process }
        elseif ($targetEnvironment -eq 'User') { $targetEnvironment = [System.EnvironmentVariableTarget]::User }
        elseif (($targetEnvironment -eq 'Global') -or ($targetEnvironment -eq 'Machine')) { $targetEnvironment = [System.EnvironmentVariableTarget]::Machine }
        elseif ($targetEnvironment -is [System.EnvironmentVariableTarget]) { <# NoOP #> }
        else {
            throw "ERROR: logic: incorrect targetEnvironment parameter ('$targetEnvironment') used for env()"
        }
    }
    else { $targetEnvironment = [System.EnvironmentVariableTarget]::Process }

    if($PSBoundParameters.ContainsKey('value')) {
        [environment]::setEnvironmentVariable($name,$value,$targetEnvironment)
        if (($targetEnvironment -eq [System.EnvironmentVariableTarget]::Process) -and ($null -ne $CMDenvpipe)) {
            "set " + ( CMD_SET_encode_arg("$name=$value") ) | out-file $CMDenvpipe -encoding DEFAULT -append
        }
    }
    else { [environment]::getEnvironmentVariable($name,$targetEnvironment) }
}
function unzip($path,$to) {
    if(!(test-path $path)) { abort "can't find $path to unzip"}
    try { add-type -assembly "System.IO.Compression.FileSystem" -ea stop }
    catch { unzip_old $path $to; return } # for .net earlier than 4.5
    if(sevenzip_installed) {
        extract_7zip $path $to $false
    }
    else {
        try {
            [io.compression.zipfile]::extracttodirectory($path,$to)
        } catch [system.io.pathtoolongexception] {
            abort "unzip failed: Windows can't handle the long paths in this zip file.`nrun 'scoop install 7zip' and try again."
        } catch {
            abort "unzip failed: $_"
        }
    }
}
function unzip_old($path,$to) {
    # fallback for .net earlier than 4.5
    $shell = (new-object -com shell.application -strict)
    $zipfiles = $shell.namespace("$path").items()
    $to = ensure $to
    $shell.namespace("$to").copyHere($zipfiles, 4) # 4 = don't show progress dialog
}

function movedir($from, $to) {
    $from = $from.trimend('\')
    $to = $to.trimend('\')

    $out = robocopy "$from" "$to" /e /move
    if($lastexitcode -ge 8) {
        throw "error moving directory: `n$out"
    }
}

function shim($path, $global, $name, $arg) {
    if(!(test-path $path)) { abort "can't shim $(fname $path): couldn't find $path" }
    $abs_shimdir = ensure (shimdir $global)
    if(!$name) { $name = strip_ext (fname $path) }

    $shim = "$abs_shimdir\$($name.tolower()).ps1"

    # convert to relative path
    push-location $abs_shimdir
    $shimdir_relative_path = resolve-path -relative $path
    pop-location

    write-output "`$path = join-path `"`$(`$MyInvocation.MyCommand.Path | Split-Path)`" `"$shimdir_relative_path`"" | out-file $shim -encoding DEFAULT
    if($arg) {
        write-output "`$args = '$($arg -join "', '")', `$args" | out-file $shim -encoding DEFAULT -append
    }
    write-output 'if($myinvocation.expectingInput) { $input | & "$path" @args } else { & "$path" @args }' | out-file $shim -encoding DEFAULT -append

    if($path -match '\.exe$') {
        # for programs with no awareness of any shell
        $shim_exe = "$(strip_ext($shim)).shim"
        copy-item "$(versiondir 'scoop' 'current')\supporting\shimexe\shim.exe" "$(strip_ext($shim)).exe" -force
        write-output "path = $shimdir_relative_path" | out-file $shim_exe -encoding DEFAULT
        if($arg) {
            write-output "args = $arg" | out-file $shim_exe -encoding DEFAULT -append
        }
    } elseif($path -match '\.((bat)|(cmd))$') {
        # shim .bat, .cmd so they can be used by programs with no awareness of PSH
        # NOTE: this code transfers execution flow via hand-off, not a call, so any modifications if/while in-progress are safe
        $shim_cmd = "$(strip_ext($shim)).cmd"
        "@`"%~dp0.\$shimdir_relative_path`" $arg %*"         | out-file $shim_cmd -encoding DEFAULT
    } elseif($path -match '\.ps1$') {
        # make ps1 accessible from cmd.exe
        $shim_cmd = "$(strip_ext($shim)).cmd"
        # default code; NOTE: only scoop knows about and manipulates shims so, by default, no special care is needed for other apps
        $code = "@powershell -noprofile -ex unrestricted `"& '%~dp0.\$shimdir_relative_path' $arg %* ; exit `$lastexitcode`""
        if ($name -eq 'scoop') {
            # shimming self; specialized code is required
            $code = shim_scoop_cmd_code $shim_cmd $path $arg
        }
        $code | out-file $shim_cmd -encoding DEFAULT
    }
}

function shim_scoop_cmd_code($shim_cmd_path, $path, $arg) {
    # specialized code for the scoop CMD shim
    # * special handling is needed for in-progress updates
    # * additional code needed to pipe environment variables back up and into to the original calling CMD process (see shim_scoop_cmd_code_body())

    # swallow errors for the case of non-existent CMD shim (eg, during initial installation)
    $CMD_shim_fullpath = resolve-path $shim_cmd_path -ea SilentlyContinue
    $CMD_shim_content = $null
    if ($CMD_shim_fullpath) {
        $CMD_shim_content = Get-Content $CMD_shim_fullpath
        }

    # prefix code ## handle in-progress updating
    # updating an in-progress BAT/CMD must be done with precise pre-planning to avoid unanticipated execution paths (and associated possible errors)
    # NOTE: must assume that the scoop CMD shim may be currently executing (since there is no simple way to determine that condition)

    # NOTE: if existent, the current scoop CMD shim is in one of two states:
    # 1. update-naive (older) version which calls scoop.ps1 via powershell as the last statement
    #    - control flow returns to the script, executing from the character position just after the call statement
    #    - notably, the position is determined *when the call was initially made in the original source* ignoring any script changes
    # 2. update-enabled version (by using either an exiting line/block or proxy execution) which can be modified without limitation

    $safe_update_signal_text = '*(scoop:#update-enabled)' # "magic" signal string ## the presence of this signal within a shim indicates that it is designed to allow in-progress updates with safety

    $code = "@::$safe_update_signal_text`r`n"

    if ($CMD_shim_content -and (-not ($CMD_shim_content -cmatch [regex]::Escape($safe_update_signal_text)))) {
        # current shim is update-naive
        $code += '@goto :__START__' + "`r`n"  # embed code for correct future executions; jumps past any buffer segment
        # buffer the prefix with specifically designed & sized code for safe return/completion of current execution
        $buffer_text = ''
        $CMD_shim_original_size = (Get-ChildItem $CMD_shim_fullpath).length
        $size_diff = $CMD_shim_original_size - $code.length
        if ($size_diff -lt 0) {
            # errors may occur upon exiting, ask user for re-run to help normalize the situation
            warn 'scoop encountered an update inconsistency, please re-run "scoop update"'
        }
        elseif ( $size_diff -gt 0 ) {
            # note: '@' characters, acting as NoOPs, are used to reduce the risk of wrong command execution in the case that we've miscalculated the return/continue location of the execution pointer
            if ( $size_diff -eq 1 ) { $buffer_text = '@' <# no room for EOL CRLF #>}
            else { $buffer_text = $('@' * ($size_diff-2)) + "`r`n" }
        }
        $code += $buffer_text + '@goto :EOF &:: safely end a returning, and now modified, in-progress script' + "`r`n"
        $code += '@:__START__' + "`r`n"
    }

    # body code ## handles update-enabled scoop call and the environment variable pipe
    $code += shim_scoop_cmd_code_body $shimdir_relative_path $arg

    $code
}

function shim_scoop_cmd_code_body($shimdir_relative_path, $arg) {
# shim startup / initialization code
$code = '
@set "ERRORLEVEL="
@setlocal
@echo off
set __ME=%~n0

:: NOTE: flow of control is passed (with *no return*) from this script to a proxy BAT/CMD script; any modification of this script is safe at any execution time after that control hand-off

:: require temporary files
:: * (needed for both out-of-source proxy contruction and for piping in-process environment variable updates)
call :_tempfile __oosource "%__ME%.oosource" ".bat"
if NOT DEFINED __oosource ( goto :TEMPFILE_ERROR )
call :_tempfile __pipe "%__ME%.pipe" ".bat"
if NOT DEFINED __pipe ( goto :TEMPFILE_ERROR )
goto :TEMPFILES_FOUND
:TEMPFILES_ERROR
echo %__ME%: ERROR: unable to open needed temporary file(s) [make sure to set TEMP or TMP to an available writable temporary directory {try "set TEMP=%%LOCALAPPDATA%%\Temp"}] 1>&2
goto __nonexistent_label_to_shift_into_command_line_context__ 2>NUL || %COMSPEC% /c exit -1
:TEMPFILES_FOUND
'
# shim code initializing environment pipe
$code += '
@::* initialize environment pipe
echo @:: TEMPORARY source/exec environment pipe [owner: "%~f0"] > "%__pipe%"
'
# shim code initializing proxy
$code += '
@::* initialize out-of-source proxy and add proxy initialization code
echo @:: TEMPORARY out-of-source executable proxy [owner: "%~f0"] > "%__oosource%"
echo (set ERRORLEVEL=) >> "%__oosource%"
echo setlocal >> "%__oosource%"
'
# shim code adding scoop call to proxy
$code += "
@::* out-of-source proxy code to call scoop
echo call powershell -NoProfile -ExecutionPolicy unrestricted -Command ^`"^& '%~dp0.\$shimdir_relative_path' -__CMDenvpipe '%__pipe%' $arg %*^`" >> `"%__oosource%`"
"
# shim code adding piping of environment changes and cleanup/exit to proxy
$code += '
@::* out-of-source proxy code to source environment changes and cleanup
echo (set __exit_code=%%ERRORLEVEL%%) >> "%__oosource%"
echo ^( endlocal >> "%__oosource%"
echo call ^"%__pipe%^"  >> "%__oosource%"
echo call erase /q ^"%__pipe%^" ^>NUL 2^>NUL >> "%__oosource%"
echo start ^"^" /b ^"%COMSPEC%^" /c del ^"%%~f0^" ^& goto __nonexistent_label_to_shift_into_command_line_context__ 2^>NUL ^|^| ^"%COMSPEC%^" /c exit %%__exit_code%% >> "%__oosource%"
echo ^) >> "%__oosource%"
'
# shim code to hand-off execution to the proxy (makes this shim "update-enabled")
$code += '
endlocal & "%__oosource%" &:: hand-off to proxy; intentional non-call (no return from proxy) to allow for safe updates of this script
'
# shim script subroutines
$code += '
goto :EOF
::#### SUBs

::
:_tempfile ( ref_RETURN [PREFIX [EXTENSION]])
:: open a unique temporary file
:: RETURN == full pathname of temporary file (with given PREFIX and EXTENSION) [NOTE: has NO surrounding quotes]
:: PREFIX == optional filename prefix for temporary file
:: EXTENSION == optional extension (including leading ".") for temporary file [default == ".bat"]
setlocal
set "_RETval="
set "_RETvar=%~1"
set "prefix=%~2"
set "extension=%~3"
if NOT DEFINED extension ( set "extension=.bat")
:: find a temp directory (respect prior setup; default to creating/using "%LocalAppData%\Temp" as a last resort)
if NOT EXIST "%temp%" ( set "temp=%tmp%" )
if NOT EXIST "%temp%" ( mkdir "%LocalAppData%\Temp" 2>NUL & cd . & set "temp=%LocalAppData%\Temp" )
if NOT EXIST "%temp%" ( goto :_tempfile_RETURN )    &:: undefined TEMP, RETURN (with NULL result)
:: NOTE: this find unique/instantiate loop has an unavoidable race condition (but, as currently coded, the real risk of collision is virtually nil)
:_tempfile_find_unique_temp
set "_RETval=%temp%\%prefix%.%RANDOM%.%RANDOM%%extension%" &:: arbitrarily lower risk can be obtained by increasing the number of %RANDOM% entries in the file name
if EXIST "%_RETval%" ( goto :_tempfile_find_unique_temp )
:: instantiate tempfile
echo|set /p OUTPUT="" >"%_RETval%"
:_tempfile_find_unique_temp_DONE
:_tempfile_RETURN
endlocal & set %_RETvar%^=%_RETval%
goto :EOF
::

goto :EOF
'
$code
}

function ensure_in_path($dir, $global) {
    $dir = fullpath $dir

    # trace "ensure_in_path(): dir = '$dir'"

    # ToDO: test with path non-existant (may need several `-erroraction silentlycontinue`)
    $shim_dir = normalize_path $(shimdir $global)
    $shim_dir_parent = normalize_path $($shim_dir + '/..')

    # trace "ensure_in_path(): shim_dir = '$shim_dir'"
    # trace "ensure_in_path(): shim_dir = '$shim_dir_parent'"

    # future sessions
    $p = env 'path' -t $global
    $was_present, $currpath = strip_path $p $dir
    if ( -not $was_present ) { write-output "adding '$dir' to $(if($global){'global'}else{'your'}) path" }
    # trace "ensure_in_path(): currpath = '$currpath'"
    $paths = split_pathlist $currpath
    # trace "ensure_in_path(): [paths]`n$paths"
    # trace "ensure_in_path(): paths.count = $($paths.count)"
    if ($paths.count -lt 1) { $paths = @( $dir ) }
    else {
        $index = [System.Array]::IndexOf( $paths, @( @( $paths ) -imatch $('^'+[regex]::escape($shim_dir_parent)) )[0] )
        if ( $index -lt 0 ) { $index = $paths.count }
        if ( $paths[$index] -ine $shim_dir ) { $index -= 1 }    # place after $shim_dir but before any other scoop dir
        $new_paths = $paths[0..$index] + $dir + $( if ($index -lt $paths.count) { $paths[$($index+1)..$paths.count] } )
        $paths = $new_paths
    }
    # trace "ensure_in_path(): [paths]`n$paths"
    # trace "ensure_in_path(): paths.count = $($paths.count)"
    env 'path' -t $global $( $paths -join ';' )

    # this session / current process
    $null, $env:path = strip_path $env:path $dir
    $paths = split_pathlist $env:path
    # trace "ensure_in_path(): [paths]`n$paths"
    # trace "ensure_in_path(): paths.count = $($paths.count)"
    if ($paths.count -lt 1) { $paths = @( $dir ) }
    else {
        $index = [System.Array]::IndexOf( $paths, @( @( $paths ) -imatch $('^'+[regex]::escape($shim_dir_parent)) )[0] )
        if ( $index -lt 0 ) { $index = $paths.count }
        if ( $paths[$index] -ine $shim_dir ) { $index -= 1 }    # place after $shim_dir but before any other scoop dir
        $new_paths = $paths[0..$index] + $dir + $( if ($index -lt $paths.count) { $paths[$($index+1)..$paths.count] } )
        $paths = $new_paths
    }
    # trace "ensure_in_path(): [paths]`n$paths"
    # trace "ensure_in_path(): paths.count = $($paths.count)"
    env 'path' $( $paths -join ';' )
}

function strip_path($orig_path, $dir) {
    $dir = normalize_path $dir
    $stripped = [string]::join(';', @( split_pathlist $orig_path | where-object { $_ -and $_ -ine $dir } ))
    ($stripped -ine $orig_path), $stripped
}

function remove_from_path($dir,$global) {
    $dir = fullpath $dir

    # future sessions
    $was_in_path, $newpath = strip_path (env 'path' -t $global) $dir
    if($was_in_path) {
        write-output "removing '$dir' from your path"
        env 'path' -t $global $newpath
    }

    # current session
    $was_in_path, $newpath = strip_path $env:path $dir
    if($was_in_path) { env 'path' $newpath }
}

function ensure_scoop_in_path($global) {
    $abs_shimdir = ensure (shimdir $global)
    # be aggressive (b-e-aggressive) and install scoop first in the path
    ensure_in_path $abs_shimdir $global
}

function ensure_robocopy_in_path {
    if(!(get-command robocopy -ea SilentlyContinue)) {
        shim "C:\Windows\System32\Robocopy.exe" $false
    }
}

function wraptext($text, $width) {
    if(!$width) { $width = $host.ui.rawui.windowsize.width };
    $width -= 1 # be conservative: doesn't seem to print the last char

    $text -split '\r?\n' | foreach-object {
        $line = ''
        $_ -split ' ' | foreach-object {
            if($line.length -eq 0) { $line = $_ }
            elseif($line.length + $_.length + 1 -le $width) { $line += " $_" }
            else { $lines += ,$line; $line = $_ }
        }
        $lines += ,$line
    }

    $lines -join "`n"
}

function pluralize($count, $singular, $plural) {
    if($count -eq 1) { $singular } else { $plural }
}

function CMD_SET_encode_arg {
    # CMD_SET_encode_arg( @ )
    # encode string(s) to equivalent CMD command line interpretable version(s) as arguments for SET
    if ($null -ne $args) {
        $args | ForEach-Object {
            $val = $_
            $val = $($val -replace '\^','^^')
            $val = $($val -replace '\(','^(')
            $val = $($val -replace '\)','^)')
            $val = $($val -replace '<','^<')
            $val = $($val -replace '>','^>')
            $val = $($val -replace '\|','^|')
            $val = $($val -replace '&','^&')
            $val = $($val -replace '"','^"')
            $val = $($val -replace '%','^%')
            $val
            }
        }
    }

function ConvertFrom-JsonNET {
    # scratch implementation, based on ideas/concepts from Brian Rogers and bradgonesurfing [1]
    # [1]: http://stackoverflow.com/questions/5546142/how-do-i-use-json-net-to-deserialize-into-nested-recursive-dictionary-and-list/19140420#19140420
    [CmdletBinding()]
    param(
        [parameter(mandatory=$True, ValueFromPipeline=$True)] [string]$json_string
        )
    BEGIN {
        $json_module_name = 'Newtonsoft.Json'
        if ( $null -eq $([System.AppDomain]::CurrentDomain.GetAssemblies() | where-object { $_.GetName().Name -eq $json_module_name }) ) {
            # avoid `import-module` which maintains an open handle on any loaded assembly .dll file until the parent assembly is shut down
            # instead, use NET `[Reflection.Assembly]::Load(...)` to load the assembly from an in-memory copy
            [System.Reflection.Assembly]::Load( [System.IO.File]::ReadAllBytes($(resolve-path $(rootrelpath "vendor\Newtonsoft.Json\lib\net20\$json_module_name.dll"))) ) | out-null
            # trace "ConvertFrom-JsonNET(): $json_module_name loaded"
        }
        $f_ToObject = { param( $token )
            $type = $token.psobject.TypeNames -imatch "Newtonsoft\..*(JObject|JArray|JProperty|JValue)"
            if (-not $type) { $type = "DEFAULT" }
            # trace "ConvertFrom-JsonNET(): ToObject::$($token.psobject.TypeNames)::$type::'$($token.name)'"
            switch ( $type )
            {
                "Newtonsoft.Json.Linq.JObject"
                    {
                    # trace "ConvertFrom-JsonNET(): object::$($token.psobject.TypeNames)::'$($token.name)'=$($token.value)"
                    $children = $token.children()
                    $h = @{}
                    $children | ForEach-Object {
                        # trace "ConvertFrom-JsonNET(): object/child::$($_.psobject.TypeNames)::'$($_.name)'[$($_.count)]"
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JValue)") {
                            $h[$token.name] = $_.value
                            }
                        else { $h[$_.name] = $(& $f_ToObject $_.first) }
                        }
                    ,$h
                    break
                    }
                "Newtonsoft.Json.Linq.JArray"
                    {
                    # trace "ConvertFrom-JsonNET(): array::$($token.psobject.TypeNames)::'$($token.name)'=$($token.value)"
                    $a = @()
                    $token | ForEach-Object {
                        # trace "ConvertFrom-JsonNET(): array/token::$($_.psobject.TypeNames)::'$($_.name)'=$($_.value)"
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JValue)") {
                            $a += , $_.value
                            }
                        else { $a += , $(& $f_ToObject $_) }
                        }
                    ,$a
                    break
                    }
                default
                    {
                    #write-debug "default::$($token.psobject.TypeNames)::'$($token.name)'=$($token.value)"
                    $token.value
                    break
                    }
            }
        }
    }
    PROCESS {
        $p = [Newtonsoft.Json.Linq.JToken]::Parse( $json_string )
        # NOTE: PowerShell v3+ `ConvertFrom-Json` returns a "PSCustomObject"; avoided here because "PSCustomObject" re-serializes incorrectly
        $o = ,$(& $f_ToObject $p)
        [object]$o  ## returns "System.Array", "System.Collections.Hashtable", or basic type
    }
    END {}
}

function ConvertTo-JsonNET {
    [CmdletBinding()]
    param(
        [parameter(mandatory=$True, ValueFromPipeline=$True)][object] $object,
        [parameter(mandatory=$False)][int] $indentation = 4  ## <0 .. no indentation; >=0 set indentation and indented format; default = 4; NOTE: [int]$null => 0
        )
    BEGIN {
        $json_module_name = 'Newtonsoft.Json'
        if ( $null -eq $([System.AppDomain]::CurrentDomain.GetAssemblies() | where-object { $_.GetName().Name -eq $json_module_name }) ) {
            # avoid `import-module` which maintains an open handle on any loaded assembly .dll file until the parent assembly is shut down
            # instead, use NET `[Reflection.Assembly]::Load(...)` to load the assembly from an in-memory copy
            [System.Reflection.Assembly]::Load( [System.IO.File]::ReadAllBytes($(resolve-path $(rootrelpath "vendor\Newtonsoft.Json\lib\net20\$json_module_name.dll"))) ) | out-null
            # trace "ConvertTo-JsonNET(): $json_module_name loaded"
        }
        $list = New-Object System.Collections.Generic.List[object]
    }
    PROCESS {
        $list.add($object)
    }
    END {
        if ($list.count -eq 1) { $list = $list | select-object -first 1 }
        # [Newtonsoft.Json.JsonConvert]::SerializeObject( $list )   ## simpler implementation, but lacks formatting options
        # NOTE: indentation == 4 => output equivalent to ConvertTo-Json()
        $sb = New-Object System.Text.StringBuilder
        $sw = New-Object System.IO.StringWriter($sb)
        $writer = New-Object Newtonsoft.Json.JsonTextWriter($sw)
        if ($indentation -ge 0) {
            $writer.Formatting = [Newtonsoft.Json.Formatting]::Indented     ## indented + multiline
            $writer.Indentation = $indentation
        }
        $s = New-Object Newtonsoft.Json.JsonSerializer
        $s.Serialize( $writer, $list )
        $sw.ToString()
    }
}

# function app($app) {
#     $appname = [string]$app
#     if ($appname -match '^([^/\\]+)?(?:/|\\)([^/\\]+)$') {
#         # BUCKET/APPNAME
#         return $matches[2], $matches[1]
#     }
#     $appname, $null
# }

# function app_specs($app_spec) {
#     $app_spec = [string]$app_spec
#     if ($app_spec -match '^([^/\\]+)?(?:/|\\)([^/\\]+)$') {
#         # BUCKET/NAME
#         return $matches[2], $matches[1]
#     }
#     $name = $app_spec
#     # NAME, BUCKET, VERSION
#     $name, $null, $null
# }

function app_parse($app) { ## returns NAME, BUCKET, VARIANT
    # app == [BUCKET/]NAME[@VARIANT]
    $app = [string]$app
    $name = $null
    $bucket = $null
    $variant = $null
    # trace "app_parse(): app = $app"
    if ($app -match '^(?:([^/\\]+)?(?:/|\\))?([^/\\]+?)(?:@([^/\\]+))?$') {
        $name, $bucket, $variant = $matches[2], $matches[1], $matches[3]
    } else {
        $name = $app
    }
    # trace "app_parse(): name, bucket, variant = $name, $bucket, $variant"
    $name, $bucket, $variant
}

function app_name($app) {
    $(app_parse $app)[0]
}

function app_bucket($app) {
    $(app_parse $app)[1]
}

function app_variant($app) {
    $(app_parse $app)[2]
}

function app_normalize($app) {
    # trace "app_normalize(): app = $app"
    $name, $bucket, $variant = app_parse $app
    app $name $bucket $variant
}

function app($name, $bucket, $variant) {
    # NOTE: $variant may be passed within $name ($variant should by $null, if so)
    # trace "app(): name, bucket, variant = $name, $bucket, $variant"
    $result = "$name"
    if ($null -ne $bucket) { $result = "$bucket/$result" }
    if ($null -ne $variant) { $result = "$result@$variant" }
    $result
}

function matching_apps($apps, $app) {
    # trace "matching_apps(): () = [$apps], $app"
    $matches = @()
    $app_name = app_name( $app )
    # trace "matching_apps(): appname('$app') = $app_name"
    if ($null -ne $apps) { foreach ($a in $apps) {
        # trace "matching_apps(): a = $a"
        $n = app_name($a)
        # trace "matching_apps(): app_name($a) = $n"
        if ( $n -ieq $app_name ) { $matches += $a }
        # trace "matching_apps(): [$a] => [$matches]"
    }}
    # trace "matching_apps():DONE: [$matches]"
    $matches
}
