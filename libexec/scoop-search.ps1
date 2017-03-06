# Usage: scoop search [query]
# Summary: Search available apps
# Help: Searches for apps that are available to install.
#
# If used with [query], shows app names that match the query.
# Without [query], shows all the available apps.

# param($query)

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\buckets.ps1")
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\versions.ps1")

reset_aliases

function bin_match($manifest, $query) {
    if(!$manifest.bin) { $false; return }
    if ($null -ne $manifest.bin) { foreach($bin in $manifest.bin) {
        $exe, $alias, $args = $bin
        $fname = split-path $exe -leaf -ea stop

        if((strip_ext $fname) -match $query) { $fname; return }
        if($alias -match $query) { $alias; return }
    }}
    $false
}

function search_bucket($bucket, $query) {
    $apps = apps_in_bucket $bucket | foreach-object {
        @{ name = $_ }
    }

    if($query) {
        try {
            $query = new-object regex $query
        } catch {
            abort "invalid regular expression: $($_.exception.innerexception.message)"
        }
        $apps = $apps | where-object {
            if($_.name -match $query) { return $true }
            $bin = bin_match (manifest $_.name $bucket) $query
            if($bin) { $_.bin = $bin; $true; return }
        }
    }
    $apps | foreach-object { $_.version = (latest_version $_.name $bucket); $_ }
}

function download_json($url) {
    $progressPreference = 'silentlycontinue'
    # PowerShell v2 is missing "invoke-webrequest"; ToDO: change to use `curl`?
    try {
        $result = invoke-webrequest $url | select-object -exp content | convertfrom-json
    } catch { $null }
    $progressPreference = 'continue'
    $result
}

function github_ratelimit_reached {
    $api_link = "https://api.github.com/rate_limit"
    (download_json $api_link).rate.remaining -eq 0
}

function search_remote($bucket, $query) {
    $repo = known_bucket_repo $bucket

    $uri = [system.uri]($repo)
    if ($uri.absolutepath -match '/([a-zA-Z0-9]*)/([a-zA-Z0-9-]*)(.git|/)?') {
        $user = $matches[1]
        $repo_name = $matches[2]
        $api_link = "https://api.github.com/repos/$user/$repo_name/git/trees/HEAD?recursive=1"
        $result = download_json $api_link | select-object -exp tree | where-object {
            $_.path -match "(($query[a-zA-Z0-9-]*).json)"
        } | foreach-object { $matches[2] }
    }

    $result
}

function search_remotes($query) {
    $buckets = known_bucket_repos
    $names = $buckets | get-member -m noteproperty | select-object -exp name

    $results = $names | where-object { !(test-path $(bucketdir $_)) } | foreach-object {
        @{"bucket" = $_; "results" = (search_remote $_ $query)}
    } | where-object { $_.results }

    if ($results.count -gt 0) {
        "results from other known buckets..."
        "add them using 'scoop bucket add <name>'"
        ""
    }

    $results | foreach-object {
        "$($_.bucket) bucket:"
        $_.results | foreach-object { "  $_" }
        ""
    }
}

if ($null -ne $args) { $args | foreach-object {
    $query = $_
    @($null) + @(buckets) | foreach-object { # $null is main bucket
        $res = search_bucket $_ $query
        if($res) {
            $name = "$_"
            if(!$_) { $name = "main" }

            "$name bucket:"
            $res | foreach-object {
                $item = "  $($_.name) ($($_.version))"
                if($_.bin) { $item += " --> includes '$($_.bin)'" }
                $item
            }
            ""
        }
    }
}}

if (!$local_results -and !(github_ratelimit_reached)) {
    search_remotes $query
}

exit 0
