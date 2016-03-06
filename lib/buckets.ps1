$bucketsdir = "$scoopdir\buckets"

function bucketdir($bucket) {
    if(!$bucket) { $(rootrelpath "bucket"); return } # main bucket

    "$bucketsdir\$bucket"
}

function known_bucket_repos {
    $dir = versiondir 'scoop' 'current'
    $json = "$dir\buckets.json"
    [System.IO.File]::ReadAllText($(resolve-path $json)) | convertfrom-jsonNET -ea stop
}

function known_bucket_repo($repo_name) {
    $buckets = known_bucket_repos
    $buckets.$repo_name
}

function apps_in_bucket($bucket) {
    $dir = bucketdir $bucket
    get-childitem $dir | where-object { $_.name.endswith('.json') } | foreach-object {
        $name = $_ -replace '.json$', ''
        # trace "apps_in_bucket(): bucket/name = $bucket/$name"
        app $name $bucket
    }
}

function buckets {
    $buckets = @()
    if(test-path $bucketsdir) {
        get-childitem $bucketsdir | foreach-object { $buckets += $_.name }
    }
    $buckets
}

function find_manifest($app) {
    # trace "find_manifest(): app = $app"
    $app = app_normalize $app
    $app_name, $bucket, $variant = app_parse $app
    # trace "find_manifest(): app = $app"
    # trace "find_manifest(): app_name, bucket, variant = $app_name, $bucket, $variant"
    if ($bucket) {
        # trace "find_manifest(): bucket = $bucket"
        $manifest = manifest $app
        if ($manifest) { return $manifest, $bucket }
        return $null
    }

    $buckets = @($null) + @(buckets) # null for main bucket
    if ($null -ne $buckets) { foreach ($bucket in $buckets) {
        $app = app $app_name $bucket $variant
        $manifest = manifest $app
        if($manifest) { $manifest, $bucket; return }
    }}
}
