# Usage: scoop uninstall <app> [options]
# Summary: Uninstall an app
# Help: e.g. scoop uninstall git

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\manifest.ps1")
. $(rootrelpath "lib\help.ps1")
. $(rootrelpath "lib\install.ps1")
. $(rootrelpath "lib\versions.ps1")
. $(rootrelpath "lib\getopt.ps1")

if(!$args) { error 'ERROR: <app> argument missing'; my_usage; exit 1 }

if ($null -ne $args) { $args | foreach-object {
    $app = $_

    if($app -eq 'scoop') {
        & $(rootrelpath "bin\uninstall.ps1") $global; exit
    }

    $global = installed $app $true
    if($global -and !(is_admin)) {
        error 'ERROR: you need admin rights to disable global apps'; exit 1
    }

    $versions = @( versions $app )
    if ($null -ne $versions) { $versions | foreach-object {
        $version = $_
        $app_name = app_name $app
        $global = installed $app $true
        "uninstalling $app_name ($version)"

        $dir = versiondir $app $version $global
        try {
            test-path $dir -ea stop | out-null
        } catch [unauthorizedaccessexception] {
            abort "access denied: '$dir'; you might need to restart"
        }

        $manifest = installed_manifest $app $version $global
        $install = install_info $app $version $global
        $architecture = $install.architecture

        run_uninstaller $manifest $architecture $dir
        rm_shims $manifest $global
        env_rm_path $manifest $dir $global
        env_rm $manifest $global

        try { remove-item -r "\\?\$(resolve-path -literalpath $dir)" -ea stop -force ; info "'$dir' was removed" }
        catch { abort "couldn't remove '$dir'; it may be in use" }
    }}

    @($true, $false) | foreach-object {
        $global = $_
        $app_name = app_name $app
        if(@(versions (app $app_name) $global).count -eq 0) {
            $appdir = appdir (app $app_name) $global
            try {
                # if last install failed, the directory seems to be locked and this
                # will throw an error about the directory not existing
                remove-item -r $appdir -ea stop -force
                info "'$appdir' was removed"
            } catch {
                if((test-path $appdir)) { throw } # only throw if the dir still exists
            }
        }
    }

    if ($versions.count -gt 0) { success "'$app' was uninstalled" } else { warn "'$app' was not found" }
}}

exit 0
