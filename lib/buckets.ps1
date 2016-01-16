$bucketsdir = "$scoopdir\buckets"

function bucketdir($name) {
    if(!$name) { return $(rootrelpath "bucket") } # main bucket

    "$bucketsdir\$name"
}

function known_bucket_repos {
    $dir = versiondir 'scoop' 'current'
    $json = "$dir\buckets.json"
    [System.IO.File]::ReadAllText($(resolve-path $json)) | convertfrom-json -ea stop
}

function known_bucket_repo($name) {
    $buckets = known_bucket_repos
    $buckets.$name
}

function apps_in_bucket($dir) {
    get-childitem $dir | where-object { $_.name.endswith('.json') } | foreach-object { $_ -replace '.json$', '' }
}

function buckets {
    $buckets = @()
    if(test-path $bucketsdir) {
        get-childitem $bucketsdir | foreach-object { $buckets += $_.name }
    }
    $buckets
}

function find_manifest($app, $bucket) {
    if ($bucket) {
        $manifest = manifest $app $bucket
        if ($manifest) { return $manifest, $bucket }
        return $null
    }

    $buckets = @($null) + @(buckets) # null for main bucket
    if ($null -ne $buckets) { foreach ($bucket in $buckets) {
        $manifest = manifest $app $bucket
        if($manifest) { return $manifest, $bucket }
    }}
}
