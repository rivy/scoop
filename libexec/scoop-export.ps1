# Usage: scoop export > filename
# Summary: Exports (an importable) list of installed apps
# Help: Lists all installed apps.

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\versions.ps1")
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\buckets.ps1")

$local = installed_apps $false | foreach-object { @{ app = $_; name = app_name $_; global = $false } }
$global = installed_apps $true | foreach-object { @{ app = $_; name = app_name $_; global = $true } }

$results = @($local) + @($global)
$count = 0

# json
# echo "{["

if($results) {
    $results | sort-object { $_.name } | where-object { !$query -or ($_.name -match $query) } | foreach-object {
        $app = $_.app
        $global = $_.global
        $ver = current_version $app $global
        $global_display = $null; if($global) { $global_display = '*global*'}

        # json
        # $val = "{ 'name': '$app', 'version': '$ver', 'global': $($global.toString().tolower()) }"
        # if($count -gt 0) {
        #     " ," + $val
        # } else {
        #     "  " + $val
        # }

        # "$app (v:$ver) global:$($global.toString().tolower())"
        "$app (v:$ver) $global_display"

        $count++
    }
}

# json
# echo "]}"

exit 0
