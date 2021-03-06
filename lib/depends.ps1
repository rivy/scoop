# resolve dependencies for the supplied apps, and sort into the correct order
function install_order($apps, $arch) {
    $res = @()
    if ($null -ne $apps) { foreach ($app in $apps) {
        $deps = @( deps $app $arch )
        if ($null -ne $deps) { foreach ($dep in $deps) {
            if($res -notcontains $dep) { $res += $dep}
        }}
        if($res -notcontains $app) { $res += $app }
    }}
    $res
}

# http://www.electricmonk.nl/docs/dependency_resolving_algorithm/dependency_resolving_algorithm.html
function deps($app, $arch) {
    $resolved = new-object collections.arraylist
    dep_resolve $app $arch $resolved @()

    if($resolved.count -eq 1) { @(); return } # no dependencies
    $resolved[0..($resolved.count - 2)]
}

function dep_resolve($app, $arch, $resolved, $unresolved) {
    $unresolved += $app

    $query = $app
    $app, $bucket = app $query
    $null, $manifest, $null, $null = locate $app $bucket
    if(!$manifest) { abort "couldn't find manifest for $query" }

    $deps = @(install_deps $manifest $arch) + @(runtime_deps $manifest) | select-object -uniq

    if ($null -ne $deps) { foreach ($dep in $deps) {
        if($resolved -notcontains $dep) {
            if($unresolved -contains $dep) {
                abort "circular dependency detected: $app -> $dep"
            }
            dep_resolve $dep $arch $resolved $unresolved
        }
    }}
    $resolved.add($app) > $null
    $unresolved = $unresolved -ne $app # remove from unresolved
}

function runtime_deps($manifest) {
    if($manifest.depends) { $manifest.depends }
}

function install_deps($manifest, $arch) {
    $deps = @()

    if(requires_7zip $manifest $arch) { $deps += "7zip" }
    if(requires_lessmsi $manifest $arch) { $deps += "lessmsi" }
    if($manifest.innosetup) { $deps += "innounp" }

    $deps
}
