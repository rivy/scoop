# Usage: scoop list [query]
# Summary: List installed apps
# Help: Lists all installed apps, or the apps matching the supplied query.
param($query)

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\versions.ps1")
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\buckets.ps1")
. $(rootrelpath "lib\install.ps1")

reset_aliases

$local = installed_apps $false | foreach-object { @{ app = $_ ; name = app_name $_ ; global = $false } }
$global = installed_apps $true | foreach-object { @{ app = $_ ; name = app_name $_ ; global = $true } }

$results = @($local) + @($global)

if($results) {
    # write-output "installed apps$(if($query) { `" matching '$query'`"}):`n"
    $results | sort-object { $_.name } | where-object { !$query -or ($_.name -match $query) } | foreach-object {
        $app = $_.app
        $app_name = $_.name
        $global = $_.global
        $version = current_version $app $global
        # trace "scoop-list: app, app_name, global, version = $app, $app_name, $global, $version"
            ## is_disabled() ...or instead, is_altered()? ... or check $(app # PATHs/shims expected) == $(PATHs/shims found)
            $disabled = $true
            $alterations = @()
                $manifest = installed_manifest $app $version $global
                $current_paths = split_pathlist (env 'PATH')
                # $global_paths = split_pathlist (env 'PATH' -t $true)
                # $user_paths = split_pathlist (env 'PATH' -t $false)
                    $partially_disabled = $false
                    $partially_enabled = $false
                        # if ($manifest.env_add_path) { write-host -fore darkmagenta "$app_name`: $($manifest.env_add_path)" }
                        if ($null -ne $manifest.env_add_path) { $manifest.env_add_path | where-object { $null -ne $_ } | foreach-object {
                            $path_base = "$(versiondir $app $version $global)\$_"
                            # trace "path_base = $path_base"
                            $path_base_resolved = resolve-path $path_base -ea 'silentlycontinue'
                            # trace "path_base_resolved = $path_base_resolved"
                            $path = normalize_path $path_base_resolved
                            # trace "path = $path"
                            if ( $path -and $( $current_paths | where-object { $_ -and $_ -ieq $path } ) ) { $partially_enabled = $true } else { $partially_disabled = $true }
                            }}
                    if ( $partially_disabled ) { $alterations += @( 'PATH entries: ' + $(if ( $partially_enabled ) { 'incomplete' } else { 'missing' }) ) }
                    $disabled = $disabled -and -not $partially_enabled

                    $partially_disabled = $false
                    $partially_enabled = $false
                        if ($null -ne $manifest.bin) { $manifest.bin | where-object { $null -ne $_ } | foreach-object {
                            $null, $fname, $null = shim_def $_
                            # trace "fname = $fname"
                            $shim = "$(shimdir $global)\$fname.ps1" # all shims have at least a FNAME.ps1 file
                            # trace "shim = $shim"
                            if ( test-path $shim ) { $partially_enabled = $true } else { $partially_disabled = $true }
                            }}
                    if ( $partially_disabled ) { $alterations += @( 'shims: ' + $( if ( $partially_enabled ) { 'incomplete' } else { 'missing' } ) ) }
                    $disabled = $disabled -and -not $partially_enabled

        $annotations = @()
        if ( $global ) { $annotations += "global" }
        if ( $disabled ) { $annotations += "* disabled" } elseif ( $alterations ) { $annotations += $('* altered (' + ($alterations -join ', ') + ')') }

        $color = $host.UI.RawUI.ForegroundColor
        if ( $global ) { $color = 'yellow' }
        if ( $disabled -or $alterations ) { $color = 'darkyellow' }
        write-host -fore $color $("  $app_name ($version) " + $(if ($annotations.count -gt 0) { "[$($annotations -join ', ')]" }))
    }
    write-host ""
    exit 0
} else {
    warn "there aren't any apps installed"
    exit 1
}
