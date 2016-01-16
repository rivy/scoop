#requires -version 2
param(
    [parameter(mandatory=$false)][int] $__updateRestart = 0,
    [parameter(mandatory=$false)][string] $__CMDenvpipe = $null,
    [parameter(mandatory=$false,position=0)] $__cmd,
    [parameter(ValueFromRemainingArguments=$true)][array] $__args = @()
    )

set-strictmode -off

$env:SCOOP__updateRestart = $__updateRestart
$env:SCOOP__CMDenvpipe = $__CMDenvpipe
$env:SCOOP__rootExecPath = $($MyInvocation.MyCommand.Path | Split-Path)

. "$env:SCOOP__rootExecPath\..\lib\core.ps1"
. $(rootrelpath 'lib\commands')

reset_aliases

$commands = commands

if (@($null, '-h', '--help', '/?') -contains $__cmd) { exec 'help' $__args }
elseif ($commands -contains $__cmd) { exec $__cmd $__args }
else { "scoop: '$__cmd' isn't a scoop command. See 'scoop help'"; exit 1 }
