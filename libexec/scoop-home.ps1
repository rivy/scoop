# Usage: scoop home <app>
# Summary: Opens the app homepage
param($app)

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\help.ps1")
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\buckets.ps1")

reset_aliases

if($app) {
    $manifest, $bucket = find_manifest $app
    if($manifest) {
        if([string]::isnullorempty($manifest.homepage)) {
            abort "could not find homepage in manifest for '$app'"
        }
        start-process $manifest.homepage
    }
    else {
        abort "could not find manifest for '$app'"
    }
} else { my_usage }

exit 0
