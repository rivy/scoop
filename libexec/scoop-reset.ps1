# Usage: scoop reset <app>
# Summary: Reset an app to resolve conflicts
# Help: Used to resolve conflicts in favor of a particular app. For example,
# if you've installed 'python' and 'python27', you can use 'scoop reset' to switch between
# using one or the other.

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\help.ps1")
. $(rootrelpath "lib\install.ps1")
. $(rootrelpath "lib\versions.ps1")

if(!$args) { 'ERROR: <app> missing'; my_usage; exit 1 }

if ($null -ne $args) { $args | foreach-object {
    $app = $_

    $global = installed $app $true
    if($global -and !(is_admin)) {
        'ERROR: you need admin rights to reset global apps'; exit 1
    }

    if(!(installed $app $global)) { abort "$app isn't installed" }

    $version = current_version $app $global
    "resetting $app ($version)"

    $dir = resolve-path (versiondir $app $version $global)
    $manifest = installed_manifest $app $version $global

    create_shims $manifest $dir $global
    env_add_path $manifest $dir $global
    env_set $manifest $dir $global
}}
