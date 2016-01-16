# Usage: scoop list [query]
# Summary: List installed apps
# Help: Lists all installed apps, or the apps matching the supplied query.
param($query)

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\versions.ps1")
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\buckets.ps1")

reset_aliases

$local = installed_apps $false | foreach-object { @{ name = $_ } }
$global = installed_apps $true | foreach-object { @{ name = $_; global = $true } }

$apps = @($local) + @($global)

if($apps) {
    write-output "Installed apps$(if($query) { `" matching '$query'`"}):
"
    $apps | sort-object { $_.name } | where-object { !$query -or ($_.name -match $query) } | foreach-object {
        $app = $_.name
        $global = $_.global
        $ver = current_version $app $global
        $global_display = $null; if($global) { $global_display = '*global*'}

        "  $app ($ver) $global_display"
    }
    ""
    exit 0
} else {
    "there aren't any apps installed"
    exit 1
}
