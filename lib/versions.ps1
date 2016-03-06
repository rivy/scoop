# versions
function latest_version($app, $url) {
    (manifest $app $url).version
}
function current_version($app, $global) {
    @(versions $app $global)[-1]
}
function versions($app, $global) {
    $appdir = appdir $app $global
    if(!(test-path $appdir)) { @(); return }

    sort_versions ($(get-childitem $appdir | where-object { $_.PSIsContainer }) | foreach-object { $_.name })
}

function version($ver) {
    $ver.split('.') | foreach-object {
        $num = $_ -as [int]
        if($num) { $num } else { $_ }
    }
}
function compare_versions($a, $b) {
    $ver_a = @(version $a)
    $ver_b = @(version $b)

    for($i=0;$i -lt $ver_a.length;$i++) {
        if($i -gt $ver_b.length) { 1; return }

        # don't try to compare int to string
        if($ver_b[$i] -is [string] -and $ver_a[$i] -isnot [string]) {
            $ver_a[$i] = "$($ver_a[$i])"
        }

        if($ver_a[$i] -gt $ver_b[$i]) { 1; return }
        if($ver_a[$i] -lt $ver_b[$i]) { -1; return }
    }
    if($ver_b.length -gt $ver_a.length) { -1; return }
    0
}

function qsort($ary, $fn) {
    if($null -eq $ary) { @(); return }
    if(!($ary -is [array])) { @($ary); return }

    $pivot = $ary[0]
    $rem = $ary[1..($ary.length-1)]

    $lesser = qsort ($rem | where-object { (& $fn $_ $pivot) -lt 0 }) $fn

    $greater = qsort ($rem | where-object { (& $fn $_ $pivot) -ge 0 }) $fn

    @() + $lesser + @($pivot) + $greater
}
function sort_versions($versions) { qsort $versions compare_versions }
