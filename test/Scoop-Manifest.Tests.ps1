write-host -f darkyellow "[$(split-path -leaf $MyInvocation.MyCommand.Path)]"

. "$psscriptroot\lib\Scoop-TestLib.ps1"
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent.FullName

describe "manifest-validation" {
    $bucketdir = "$repo_dir\bucket"
    $files = get-childitem $bucketdir *.json

    $files_exist = ($files.Count -gt 0)

    it $('manifest files exist ({0} found)' -f $files.Count) -skip:$(-not $files_exist) {
        if (-not ($files.Count -gt 0))
        {
            throw "No manifest files were found"
        }
    }

    it "manifest files are valid" -skip:$(-not $files_exist) {
        $badFiles = @(
            foreach ($file in $files)
            {
                try { $manifest = parse_json $file.fullname } catch { "[$($file.Name)]: Invalid json format"; continue }

                $url = arch_specific "url" $manifest "32bit"
                if(!$url) {
                    $url = arch_specific "url" $manifest "64bit"
                }

                try { $null = $url | should not benullorempty } catch { "[$($file.Name)] `$url: "+$error[0].Exception.Message }
                try { $null = $manifest | should not benullorempty } catch { "[$($file.Name)] `$manifest: "+$error[0].Exception.Message }
                try { $null = $manifest.version | should not benullorempty } catch { "[$($file.Name)] `$manifest.version: "+$error[0].Exception.Message }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following errors were found:`n$($badFiles -join "`n")"
        }
    }
}

describe "parse_json" {
    beforeall {
        $working_dir = setup_working "parse_json"
    }

    context "json is invalid" {
        it "fails with invalid json" {
            { parse_json "$working_dir\wget.json" } | should throw
        }
    }
}
