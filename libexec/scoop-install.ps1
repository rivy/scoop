# Usage: scoop install <app> [options]
# Summary: Install apps
# Help: e.g. The usual way to install an app (uses your local 'buckets'):
#      scoop install git
#
# To install an app from a manifest at a URL:
#      scoop install https://raw.github.com/lukesampson/scoop/master/bucket/runat.json
#
# To install an app from a manifest on your computer
#      scoop install \path\to\app.json
#
# When installing from your computer, you can leave the .json extension off if you like.
#
# Options:
#   -a, --arch <32bit|64bit>  use the specified architecture, if the app supports it
#   -g, --global              install the app globally
#   -k, --no-cache            don't use the download cache (note: will overwrite any cached copy)

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\buckets.ps1")
. $(rootrelpath "lib\decompress.ps1")
. $(rootrelpath "lib\install.ps1")
. $(rootrelpath "lib\versions.ps1")
. $(rootrelpath "lib\help.ps1")
. $(rootrelpath "lib\getopt.ps1")
. $(rootrelpath "lib\depends.ps1")
. $(rootrelpath "lib\config.ps1")

function warn_installed($apps, $global) {
    $apps = @(all_installed $apps $global)
    if ($null -ne $apps) { $apps | foreach-object {
        $app = $_
        if($app) {
            $app_name = app_name $app
            $version = @(versions $app $global)[-1]
            warn "$app_name ($version) is already installed. Use 'scoop update $app_name$global_flag' to update to a newer version."
        }

    }}
}

$opt, $apps, $err = getopt $args 'a:Cgk' 'arch=', 'no-cache', 'global', 'insecure'
if($err) { "scoop install: $err"; exit 1 }

$architecture = ensure_architecture $opt.a + $opt.arch
$use_cache = !($opt.C -or $opt.'no-cache')
$global = $opt.g -or $opt.global
$allow_insecure = $opt.k -or $opt.insecure

if(!$apps) { error '<app> missing'; my_usage; exit 1 }

if($global -and !(is_admin)) {
    error 'you need admin rights to install global apps'; exit 1
}

ensure_none_failed $apps $global
warn_installed $apps $global

# trace "1:apps = $apps"
$apps = install_order $apps $architecture # adds dependencies
# trace "2:apps = $apps"
ensure_none_failed $apps $global
$apps = prune_installed $apps $global # removes dependencies that are already installed
# trace "3:apps = $apps"

$apps | foreach-object { install_app $_ $architecture $global $use_cache $allow_insecure }

exit 0
