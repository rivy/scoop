function command_files {
    (get-childitem (relpath '..\libexec')) `
        + (get-childitem "$scoopdir\shims") `
        | where-object { $_.name -match 'scoop-.*?\.ps1$' }
}

function commands {
    command_files | foreach-object { command_name $_ }
}

function command_name($filename) {
    $filename.name | select-string 'scoop-(.*?)\.ps1$' | foreach-object { $_.matches[0].groups[1].value }
}

function command_path($cmd) {
    $cmd_path = relpath "..\libexec\scoop-$cmd.ps1"

    # built in commands
    if (!(Test-Path $cmd_path)) {
        # get path from shim
        $shim_path = "$scoopdir\shims\scoop-$cmd.ps1"
        $line = ((get-content $shim_path) | where-object { $_.startswith('$path') })
        if($line) {
            invoke-expression -command "$line"
            $cmd_path = $path
        }
        else { $cmd_path = $shim_path }
    }

    $cmd_path
}

function exec($cmd, $arguments) {
    $cmd_path = command_path $cmd

    & $cmd_path @arguments
}
