$bucketsdir = "$scoopdir\buckets"

function bucketdir($name) {
    if(!$name) { return relpath "..\bucket" } # main bucket

    "$bucketsdir\$name"
}

function known_bucket_repo($name) {
    $dir = versiondir 'scoop' 'current'
    $json = "$dir\buckets.json"
    $buckets = [System.IO.File]::ReadAllText($(resolve-path $json)) | convertfrom-json -ea stop
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

function find_manifest($app) {
    $buckets = @($null) + @(buckets) # null for main bucket
    if ($null -ne $buckets) { foreach ($bucket in $buckets) {
        $manifest = manifest $app $bucket
        if($manifest) { return $manifest, $bucket }
    }}
}
