# Usage: scoop status
# Summary: Show status and check for new app versions

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\buckets.ps1")
. $(rootrelpath "lib\versions.ps1")
. $(rootrelpath "lib\depends.ps1")
. $(rootrelpath "lib\config.ps1")

# check if scoop needs updating
$currentdir = fullpath $(versiondir 'scoop' 'current')
$needs_update = $false

if ((test-path "$currentdir\.git") -and $(try { get-command 'git' -ea stop } catch { $false })) {
    push-location $currentdir
    $current_branch = & "git" @('rev-parse', '--abbrev-ref', 'HEAD', '--') 2>$null
    $null = & "git" @('fetch', '-q',  'origin') 2>$null
    $commits = & "git" @('log', "HEAD..origin/$current_branch", '--oneline') 2>$null
    if($commits) { $needs_update = $true }
    pop-location
}
else {
    $needs_update = $true
}

if($needs_update) {
    "scoop is out of date. run scoop update to get the latest changes."
}
else { "scoop is up-to-date."}

$failed = @()
$old = @()
$removed = @()
$missing_deps = @()

$true, $false | foreach-object { # local and global apps
    $global = $_
    $dir = appsdir $global
    if(!(test-path $dir)) { return }

    get-childitem $dir | where-object name -ne 'scoop' | foreach-object {
        $app = $_.name
        $version = current_version $app $global
        if($version) {
            $install_info = install_info $app $version $global
        }

        if(!$install_info) {
            $failed += @{ $app = $version }; return
        }

        $manifest = manifest $app $install_info.bucket $install_info.url
        if(!$manifest) { $removed += @{ $app = $version }; return }

        if((compare_versions $manifest.version $version) -gt 0) {
            $old += @{ $app = @($version, $manifest.version) }
        }

        $deps = @(runtime_deps $manifest) | where-object { !(installed $_) }
        if($deps) {
            $missing_deps += ,(@($app) + @($deps))
        }
    }
}



if($old) {
    "updates are available for:"
    $old.keys | foreach-object {
        $versions = $old.$_
        "    $_`: $($versions[0]) -> $($versions[1])"
    }
}

if($removed) {
    "these app manifests have been removed:"
    $removed.keys | foreach-object {
        "    $_"
    }
}

if($failed) {
    "these apps failed to install:"
    $failed.keys | foreach-object {
        "    $_"
    }
}

if($missing_deps) {
    "missing runtime dependencies:"
    $missing_deps | foreach-object {
        $app, $deps = $_
        "    $app requires $([string]::join(',', $deps))"
    }
}

if(!$old -and !$removed -and !$failed -and !$missing_deps) {
    success "everything is ok!"
}

exit 0
