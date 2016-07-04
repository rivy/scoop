. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"

# resolve dependencies for the supplied apps, and sort into the correct order
function install_order($apps, $arch) {
    # trace "install_order(): () = [$apps], $arch"
    $res = @()
    if ($null -ne $apps) { foreach ($app in $apps) {
        # trace "install_order(): app = $app"
        $deps = @( deps $app $arch )
        # trace "install_order(): deps = [$deps]"
        if ($null -ne $deps) { foreach ($dep in $deps) {
            $app_variant = @( matching_apps $apps $dep )[0];
            # trace "install_order(): app_variant = $app_variant"
            if ($null -ne $app_variant) { $dep = $app_variant }
            # trace "install_order(): dep = $dep"
            if (-not ( matching_apps $res $dep )) { $res += @( install_order $dep $arch ) }
        }}
        if($res -notcontains $app) { $res += $app } # match full app_variant for user-supplied apps
        # trace "install_order(): [app=$app] res = [$res]"
    }}
    $res
    # trace "install_order():DONE: res = [$res]"
}

# http://www.electricmonk.nl/docs/dependency_resolving_algorithm/dependency_resolving_algorithm.html
function deps($app, $arch) {
    # trace "deps(): app, arch = $app, $arch"
    # $resolved = new-object collections.arraylist
    $resolved = @( dep_resolve $app $arch @() @() )[1]
    # trace "deps(): resolved = [$resolved]"

    if($resolved.count -eq 1) { @(); return } # no dependencies
    $resolved[0..($resolved.count - 2)]
    # trace "deps(): resolved[0..] = [$($resolved[0..($resolved.count - 2)])]"
}

function dep_resolve($app, $arch, $resolved, $unresolved) {
    # trace "dep_resolve(): () = $app, $arch, [$resolved], [$unresolved]"
    $app = app_normalize $app
    # trace "dep_resolve(): app = $app"
    app_name = app_name $app

    $unresolved += $app

    # $query = $app
    # $app, $bucket = app $query
    # $null, $manifest, $null, $null = locate $app $bucket
    $null, $manifest, $null, $null = locate $app
    if(!$manifest) { abort "couldn't find manifest for '$app'" }

    $deps = @(install_deps $manifest $arch) + @(runtime_deps $manifest) | select-object -uniq
    # trace "dep_resolve(): deps = [$deps]"

    if ($null -ne $deps) { foreach ($dep in $deps) {
        # trace "dep_resolve():loop#1: resolved, unresolved = [$resolved], [$unresolved]"
        if($resolved -notcontains $dep) {
            # trace "dep_resolve():loop#2: resolved, unresolved = [$resolved], [$unresolved]"
            if($unresolved -contains $dep) {
                abort "circular dependency detected: $app_name -> $dep"
            }
            # trace "dep_resolve():loop#3: resolved, unresolved = [$resolved], [$unresolved]"
            $results = @( dep_resolve $dep $arch @($resolved) @($unresolved) )
            # trace "dep_resolve():loop#4: results = [$results]"
            $resolved = $results[1]
            $unresolved = $results[2]
            # trace "dep_resolve():loop#4: resolved, unresolved = [$resolved], [$unresolved]"
        }
    }}
    # trace "dep_resolve(): app = '$app'"
    # $resolved.add($app) > $null
    # trace "dep_resolve():pre-DONE: resolved, unresolved = [$resolved], [$unresolved]"
    $resolved += "$app"
    $unresolved = $unresolved -ne $app # remove from unresolved
    # trace "dep_resolve():DONE: resolved, unresolved = [$resolved], [$unresolved]"
    @( @($resolved), @($unresolved) )
}

function runtime_deps($manifest) {
    if($manifest.depends) { $manifest.depends }
}

function install_deps($manifest, $arch) {
    $deps = @()

    if(requires_7zip $manifest $arch) { $deps += (app "7zip") }
    if(requires_lessmsi $manifest $arch) { $deps += (app "lessmsi") }
    if($manifest.innosetup) { $deps += (app "innounp") }

    $deps
}
