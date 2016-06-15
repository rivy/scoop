# Usage: scoop cache show|rm [app]
# Summary: Show or clear the download cache
# Help: Scoop caches downloads so you don't need to download the same files
# when you uninstall and re-install the same version of an app.
#
# You can use
#     scoop cache show
# to see what's in the cache, and
#     scoop cache rm <app> to remove downloads for a specific app.
param($cmd, $app)

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\help.ps1"

reset_aliases

function cacheinfo($file) {
    $app, $version, $null, $url = $file.name -split '@'
    $size = filesize $file.length
    @{ app=$app; version=$version; url=$url; size=$size }
}

function filesize($length) {
    $gb = [math]::pow(2, 30)
    $mb = [math]::pow(2, 20)
    $kb = [math]::pow(2, 10)

    if($length -gt $gb) {
        "{0:n1} GB" -f ($length / $gb)
    } elseif($length -gt $mb) {
        "{0:n1} MB" -f ($length / $mb)
    } elseif($length -gt $kb) {
        "{0:n1} KB" -f ($length / $kb)
    } else {
        "$($length) B"
    }
}

switch($cmd) {
    'rm' {
        if(!$app) { 'ERROR: <app> missing'; my_usage; exit 1 }
        remove-item "$scoopdir\cache\$app@*"
    }
    'show' {
        $files = @(get-childitem "$scoopdir\cache" | where-object { $_.name -match "^$app" })
        $total_length = ($files | measure-object length -sum).sum

        $f_app  = @{ expression={"$($_.app) ($($_.version))" }}
        $f_url  = @{ expression={$_.url};alignment='right'}
        $f_size = @{ expression={$_.size}; alignment='right'}

        if ($null -ne $files) { $files | foreach-object { cacheinfo $_ } |
            % { new-object PSObject -Property $_ } |
            format-table $f_size, $f_app, $f_url -auto |
            out-string -stream | ? {$_}     ## remove blank lines
        }

        "total: $($files.length) $(pluralize $files.length 'file' 'files'), $(filesize $total_length)"
    }
    default {
        "cache '$cmd' not supported"; my_usage; exit 1
    }
}

exit 0
