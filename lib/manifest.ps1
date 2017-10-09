. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"

function manifest_path($app) {
    # trace "manifest_path(): app = $app"
    $name, $bucket, $variant = app_parse $app
    # trace "manifest_path(): name, bucket, variant = $name, $bucket, $variant"
    $fname = $name + $(if ($variant) { "@$variant" })
    "$(bucketdir $bucket)\$(sanitary_path $fname).json"
}

function parse_json($path) {
    if(!(test-path $path)) { $null; return }
    [System.IO.File]::ReadAllText($(resolve-path $path)) | convertfrom-jsonNET -ea stop
}

function url_manifest($url) {
    # write-host "url_manifest(): url = $url"
    $str = $null
    try {
        $str = (new-object net.webclient).downloadstring($url)
    } catch [system.management.automation.methodinvocationexception] {
        warn "error: $($_.exception.innerexception.message)"
    } catch {
        throw
    }
    if(!$str) { $null; return }
    $str | convertfrom-jsonNET
}

function manifest($app, $url) {
    if($url) { url_manifest $url; return }
    parse_json (manifest_path $app)
}

function save_installed_manifest($app, $dir, $url) {
    if($url) { (new-object net.webclient).downloadstring($url) > "$dir\manifest.json" }
    else { copy-item (manifest_path $app) "$dir\manifest.json" }
}

function installed_manifest($app, $version, $global) {
    parse_json "$(versiondir $app $version $global)\manifest.json"
}

function save_install_info($info, $dir) {
    $nulls = $info.keys | where-object { $null -eq $info[$_] }
    $nulls | foreach-object { $info.remove($_) } # strip null-valued

    $info | convertto-jsonNET | out-file "$dir\install.json"
}

function install_info($app, $version, $global) {
    $path = "$(versiondir $app $version $global)\install.json"
    if(!(test-path $path)) { $null; return }
    parse_json $path
}

function default_architecture {
    if([intptr]::size -eq 8) { "64bit"; return }
    "32bit"
}

function arch_specific($prop, $manifest, $architecture) {
    # trace "arch_specific( `$prop, `$manifest, `$architecture ) = arch_specific( $prop, $manifest, $architecture )"
    if($manifest.architecture) {
        $val = $manifest.architecture.$architecture.$prop
        if($val) { $val; return } # else fallback to generic prop
    }

    if($manifest.$prop) { $manifest.$prop; return }
}

function url($manifest, $arch) { arch_specific 'url' $manifest $arch }
function installer($manifest, $arch) { arch_specific 'installer' $manifest $arch }
function uninstaller($manifest, $arch) { arch_specific 'uninstaller' $manifest $arch }
function msi($manifest, $arch) { arch_specific 'msi' $manifest $arch }
function hash($manifest, $arch) { arch_specific 'hash' $manifest $arch }
function extract_dir($manifest, $arch) { arch_specific 'extract_dir' $manifest $arch}
function extract_to($manifest, $arch) { arch_specific 'extract_to' $manifest $arch}
