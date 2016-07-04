# Usage: scoop depends <app>
# Summary: List dependencies for an app

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\depends.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\install.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\manifest.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\buckets.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\getopt.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\decompress.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\config.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\help.ps1"

$opt, $apps, $err = getopt $args 'a:' 'arch='
$app = $apps[0]

if(!$app) { "<app> missing"; my_usage; exit 1 }

$architecture = ensure_architecture ($opt.a + $opt.architecture)

$deps = @(deps $app $architecture)
if($deps) {
    $deps[($deps.length - 1)..0]
}
