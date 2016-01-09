# Usage: scoop update <app> [options]
# Summary: Update apps, or Scoop itself
# Help: 'scoop update' updates Scoop to the latest version.
# 'scoop update <app>' installs a new version of that app, if there is one.
#
# You can use '*' in place of <app> to update all apps.
#
# Options:
#   --global, -g    update a globally installed app
#   --force, -f     force update even when there isn't a newer version
#   --no-cache, -k  don't use the download cache
#   --quiet, -q     hide extraneous messages

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\install.ps1")
. $(rootrelpath "lib\decompress.ps1")
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\buckets.ps1")
. $(rootrelpath "lib\versions.ps1")
. $(rootrelpath "lib\getopt.ps1")
. $(rootrelpath "lib\depends.ps1")
. $(rootrelpath "lib\config.ps1")

reset_aliases

$update_restart = [int]$env:SCOOP__updateRestart
$args_initial = $args

$opt, $apps, $err = getopt $args 'gfkq' 'global','force', 'no-cache', 'quiet'
if($err) { "scoop update: $err"; exit 1 }
$global = $opt.g -or $opt.global
$force = $opt.f -or $opt.force
$use_cache = !($opt.k -or $opt.'no-cache')
$quiet = $opt.q -or $opt.quiet

function update_scoop() {
    # check for git
    $git = try { get-command git -ea stop } catch { $null }
    if(!$git) { abort "scoop uses git to update itself. run 'scoop install git'." }

    write-host -nonewline "updating scoop..."
    $currentdir = fullpath $(versiondir 'scoop' 'current')
    $hash_original = ""
    if(!(test-path "$currentdir\.git")) {
        # load defaults
        $repo = $default['repo']
        $branch = $default['repo.branch']

        # remove non-git scoop
        remove-item -r -force $currentdir -ea stop

        # get git scoop
        $null = & 'git' @( 'clone', '-q', $repo, '--branch', $branch, '--single-branch', $currentdir ) 2>$null
    }
    else {
        push-location $currentdir
        $hash_original = & 'git' @( 'describe', '--all', '--always', '--long' ) 2>$null
        $current_branch = & 'git' @('rev-parse', '--abbrev-ref', 'HEAD') 2>$null
        if ($current_branch -eq 'HEAD') {
            # detached HEAD ~ fallback to using for-each-ref/merge-base
            $current_branch = $null
            # find most-recently active branch which is an ancestor of the current commit and has an upstream reference
            # git >= v2.7.0 ... $b = $(git for-each-ref --count=1 --contains HEAD --sort=-committerdate refs/heads --format=%(refname)) -replace '^refs/heads/', ''
            # ref: http://stackoverflow.com/questions/24993772/how-to-find-all-refs-that-contain-a-commit-in-their-history-in-git/24994211#24994211
            $heads = @( & 'git' @('for-each-ref', '--sort=-committerdate', 'refs/heads', '--format=%(refname)') 2>$null )
            if ($null -ne $heads) { foreach ($head in $heads) {
                if ( $(& 'git' @('merge-base', '--is-ancestor', 'HEAD', $head) 2>$null ; $LASTEXITCODE -eq 0) ) { $current_branch = $head -replace '^refs/heads/', '' }
                if ( $(& 'git' @('rev-parse', '--abbrev-ref', "$current_branch@{upstream}" ) 2>$null ; $LASTEXITCODE -eq 0) ) { break }
            }}
            if (($null -eq $current_branch) -and ( $(& 'git' @('rev-parse', '--abbrev-ref', "master@{upstream}" ) 2>$null ; $LASTEXITCODE -eq 0) )) { $current_branch = 'master' } ## last ditch default
            if ($null -ne $current_branch) {
                # save reference to current commit
                $save_name = 'update/stashed-' + $(& 'git' @( 'rev-parse', '--short=16', 'HEAD' ) 2>$null)
                $null = & 'git' @( 'branch', '--force', $save_name ) 2>$null
                #
                warn "update:(scoop): using best-guess branch ('$current_branch') for update; prior revision saved as branch '$save_name'"
            }
        }
        $upstream_ref = & 'git' @('rev-parse', '--abbrev-ref', "$current_branch@{upstream}" ) 2>$null
        if ($null -eq $upstream_ref) {
            warn 'update:(scoop): unable to find an upstream reference; you may need to reinstall "scoop"'
        } else {
            $null = & 'git' @( 'checkout', '--quiet', '--force', $current_branch ) 2>$null
            $null = & 'git' @( 'fetch', '--quiet' ) 2>$null
            $null = & 'git' @( 'checkout', '--quiet', '--force', $upstream_ref ) 2>$null
            $null = & 'git' @( 'clean', '-fd' ) 2>$null
            $null = & 'git' @( 'branch', '--quiet', '--force', $current_branch ) 2>$null
            $null = & 'git' @( 'checkout', '--quiet', '--force', $current_branch ) 2>$null
        }
        pop-location
    }
    push-location $currentdir
    $hash_new = & 'git' @( 'describe', '--all', '--always', '--long' ) 2>$null
    pop-location
    if ( $hash_new -ne $hash_original ) {
        $max_restarts = 1
        if ( $update_restart -gt $max_restarts ) {
            warn "update: scoop code was changed, please re-run 'scoop update'"
        }
        else {
            write-host "update: scoop code was changed, restarting update..."
            & $(rootrelpath "bin\scoop.ps1") update -__updateRestart $($update_restart + 1) $args_initial
            exit $lastExitCode
        }
    } elseif ( $update_restart -gt 0 ) { success 'updated' } else { write-host '(no changes)'}

    ensure_scoop_in_path $false
    shim "$currentdir\bin\scoop.ps1" $false

    @(buckets) | foreach-object {
        write-host -nonewline "updating $_ bucket..."
        $changed = $false
        push-location (bucketdir $_)
        $hash_original = & 'git' @( 'describe', '--all', '--always', '--long' ) 2>$null
        $current_branch = & 'git' @('rev-parse', '--abbrev-ref', 'HEAD') 2>$null
        if ($current_branch -eq 'HEAD') {
            # detached HEAD ~ fallback to using for-each-ref/merge-base
            $current_branch = $null
            # find most-recently active branch which is an ancestor of the current commit and has an upstream reference
            # git >= v2.7.0 ... $b = $(git for-each-ref --count=1 --contains HEAD --sort=-committerdate refs/heads --format=%(refname)) -replace '^refs/heads/', ''
            # ref: http://stackoverflow.com/questions/24993772/how-to-find-all-refs-that-contain-a-commit-in-their-history-in-git/24994211#24994211
            $heads = @( & 'git' @('for-each-ref', '--sort=-committerdate', 'refs/heads', '--format=%(refname)') 2>$null )
            if ($null -ne $heads) { foreach ($head in $heads) {
                if ( $(& 'git' @('merge-base', '--is-ancestor', 'HEAD', $head) 2>$null ; $LASTEXITCODE -eq 0) ) { $current_branch = $head -replace '^refs/heads/', '' }
                if ( $(& 'git' @('rev-parse', '--abbrev-ref', "$current_branch@{upstream}" ) 2>$null ; $LASTEXITCODE -eq 0) ) { break }
            }}
            if (($null -eq $current_branch) -and ( $(& 'git' @('rev-parse', '--abbrev-ref', "master@{upstream}" ) 2>$null ; $LASTEXITCODE -eq 0) )) { $current_branch = 'master' } ## last ditch default
            if ($null -ne $current_branch) {
                # save reference to current commit
                $save_name = 'update/stashed-' + $(& 'git' @( 'rev-parse', '--short=16', 'HEAD' ) 2>$null)
                $null = & 'git' @( 'branch', '--force', $save_name ) 2>$null
                #
                warn "update:(bucket[$_]): using best-guess branch ('$current_branch') for update; prior revision saved as branch '$save_name'"
            }
        }
        $upstream_ref = & 'git' @('rev-parse', '--abbrev-ref', "$current_branch@{upstream}" ) 2>$null
        if ($null -eq $upstream_ref) {
            warn "update:(bucket[$_]): unable to find an upstream reference; you may need to reinstall bucket '$_'"
        } else {
            $null = & 'git' @( 'checkout', '--quiet', '--force', $current_branch ) 2>$null
            $null = & 'git' @( 'fetch', '--quiet' ) 2>$null
            $null = & 'git' @( 'checkout', '--quiet', '--force', $upstream_ref ) 2>$null
            $null = & 'git' @( 'clean', '-fd' ) 2>$null
            $null = & 'git' @( 'branch', '--quiet', '--force', $current_branch ) 2>$null
            $null = & 'git' @( 'checkout', '--quiet', '--force', $current_branch ) 2>$null
            $hash_new = & 'git' @( 'describe', '--all', '--always', '--long' ) 2>$null
            $changed = ($hash_new -ne $hash_original)
        }
        pop-location
        if ($changed) { success "updated" } else { write-output '(no changes)' }
    }
}

function update($app, $global, $quiet = $false) {
    $old_version = current_version $app $global
    $old_manifest = installed_manifest $app $old_version $global
    $install = install_info $app $old_version $global
    $check_hash = $true

    # re-use architecture, bucket and url from first install
    $architecture = $install.architecture
    $bucket = $install.bucket
    $url = $install.url

    # check dependencies
    $deps = @(deps $app $architecture) | where-object { !(installed $_) }
    $deps | foreach-object { install_app $_ $architecture $global }

    $version = latest_version $app $bucket $url
    $is_nightly = $version -eq 'nightly'
    if($is_nightly) {
        $version = nightly_version $(get-date) $quiet
        $check_hash = $false
    }

    if(!$force -and ($old_version -eq $version)) {
        if (!$quiet) {
            warn "the latest version of $app ($version) is already installed."
            "run 'scoop update' to check for new versions."
        }
        return
    }
    if(!$version) { abort "no manifest available for $app" } # installed from a custom bucket/no longer supported

    $manifest = manifest $app $bucket $url

    "updating $app ($old_version -> $version)"

    $dir = versiondir $app $old_version $global

    "uninstalling $app ($old_version)"
    run_uninstaller $old_manifest $architecture $dir
    rm_shims $old_manifest $global
    env_rm_path $old_manifest $dir $global
    env_rm $old_manifest $global
    # note: keep the old dir in case it contains user files

    "installing $app ($version)"
    $dir = ensure (versiondir $app $version $global)

    # save info for uninstall
    save_installed_manifest $app $bucket $dir $url
    save_install_info @{ 'architecture' = $architecture; 'url' = $url; 'bucket' = $bucket } $dir

    $fname = dl_urls $app $version $manifest $architecture $dir $use_cache $check_hash
    unpack_inno $fname $manifest $dir
    pre_install $manifest
    run_installer $fname $manifest $architecture $dir
    ensure_install_dir_not_in_path $dir
    create_shims $manifest $dir $global
    env_add_path $manifest $dir $global
    env_set $manifest $dir $global
    post_install $manifest

    success "$app was updated from $old_version to $version"

    show_notes $manifest
}

function ensure_all_installed($apps, $global) {
    $app = $apps | where-object { !(installed $_ $global) } | select-object -first 1 # just get the first one that's not installed
    if($app) {
        if(installed $app (!$global)) {
            function wh($g) { if($g) { "globally" } else { "for your account" } }
            write-host "$app isn't installed $(wh $global), but it is installed $(wh (!$global))" -f darkred
            "try updating $(if($global) { 'without' } else { 'with' }) the --global (or -g) flag instead"
            exit 1
        } else {
            abort "$app isn't installed"
        }
    }
}

# convert list of apps to list of ($app, $global) tuples
function applist($apps, $global) {
    ,@($apps | foreach-object { ,@($_, $global) })
}

if(!$apps) {
    if($global) {
        "scoop update: --global is invalid when <app> not specified"; exit 1
    }
    if (!$use_cache) {
        "scoop update: --no-cache is invalid when <app> not specified"; exit 1
    }
    update_scoop
} else {
    if($global -and !(is_admin)) {
        'ERROR: you need admin rights to update global apps'; exit 1
    }

    if($apps -eq '*') {
        $apps = applist (installed_apps $false) $false
        if($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        ensure_all_installed $apps $global
        $apps = applist $apps $global
    }

    # $apps is now a list of ($app, $global) tuples
    $apps | foreach-object { update @_ $quiet }
}

exit 0
