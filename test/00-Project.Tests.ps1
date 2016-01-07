write-host -f darkyellow "[$(split-path -leaf $MyInvocation.MyCommand.Path)]"

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent.FullName

$repo_files = @( $(Get-ChildItem $repo_dir -recurse -force | where-object { -not $_.PSIsContainer }) )

$project_file_exclusions = @(
    $([regex]::Escape($repo_dir.fullname)+'\\.git\\.*$')
    $([regex]::Escape($repo_dir.fullname)+'\\vendor\\.*$')
)

describe 'Project code' {

    $files = @(
        $repo_files |
            where-object { $_.fullname -inotmatch $($project_file_exclusions -join '|') } |
            where-object { $_.fullname -imatch '.(ps1|psm1)$' }
    )

    $files_exist = ($files.Count -gt 0)

    it $('PowerShell code files exist ({0} found)' -f $files.Count) -skip:$(-not $files_exist) {
        if (-not ($files.Count -gt 0))
        {
            throw "No PowerShell code files were found"
        }
    }

    function Test-PowerShellSyntax {
        # ref: http://powershell.org/wp/forums/topic/how-to-check-syntax-of-scripts-automatically @@ https://archive.is/xtSv6
        # originally created by Alexander Petrovskiy & Dave Wyatt
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string[]]
            $Path
        )

        process {
            foreach ($scriptPath in $Path) {
                $contents = Get-Content -Path $scriptPath

                if ($null -eq $contents) {
                    continue
                }

                $errors = $null
                $null = [System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors)

                New-Object psobject -Property @{
                    Path = $scriptPath
                    SyntaxErrorsFound = ($errors.Count -gt 0)
                }
            }
        }
    }

    it 'PowerShell code files do not contain syntax errors' -skip:$(-not $files_exist) {
        $badFiles = @(
            foreach ($file in $files)
            {
                if ( (Test-PowerShellSyntax $file.FullName).SyntaxErrorsFound )
                {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following files have syntax errors:`n`n$($badFiles -join "`n")"
        }
    }

    $lint_module_name = 'PSScriptAnalyzer'
    $lint_module_version = '1.3.0'
    if (-not (Get-Module $lint_module_name)) {
        $filename = [System.IO.Path]::Combine($repo_dir,"vendor\$lint_module_name\$lint_module_version\$lint_module_name.psd1")
        import-module $(resolve-path $filename)
    }
    $have_delinter = Get-Module $lint_module_name

    function truthy {
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [object]
            $o
        )
        $retval = $true
        if ($null -eq $o) { $retval = $false } else {
        if ($o -is [bool]) { $retval = $o } else {
        if (($o -is [int]) -or ($o -is [long]) -or ($o -is [single]) -or ($o -is [double]) -or ($o -is [decimal])) { $retval = ($o -ne 0) } else {
            $str = [string]$o
            if ('' -eq $str) { $retval = $false }
            if ('0' -eq $str) { $retval = $false }
        }}}
        $retval
    }

    $it_desc = 'PowerShell code files have no unresolved critiques'
    $skip = -not (truthy "$env:TEST_ALL")
    if ($skip) { $it_desc += ' [to run: `$env:TEST_ALL=$true`]' }
    it $it_desc -skip:$($skip -or -not $files_exist -or -not $have_delinter) {
        $rule_exclusions = @( 'PSAvoidUsingWriteHost' )
        $badFiles = @(
            foreach ($file in $files)
            {
                if ( (Invoke-ScriptAnalyzer $file.FullName -excluderule $rule_exclusions).count )
                {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following files have lint warnings/errors:`n`n$($badFiles -join "`n")"
        }
    }

}

describe 'Style constraints for non-binary project files' {

    $files = @(
        # gather all files except '*.exe', '*.zip', or any .git repository files
        $repo_files |
            where-object { $_.fullname -inotmatch $($project_file_exclusions -join '|') } |
            where-object { $_.fullname -inotmatch '(.exe|.zip)$' }
    )

    $files_exist = ($files.Count -gt 0)

    it $('non-binary project files exist ({0} found)' -f $files.Count) -skip:$(-not $files_exist) {
        if (-not ($files.Count -gt 0))
        {
            throw "No non-binary project files were found"
        }
    }

    it 'files do not contain leading utf-8 BOM' -skip:$(-not $files_exist) {
        # utf-8 BOM == 0xEF 0xBB 0xBF
        # see http://www.powershellmagazine.com/2012/12/17/pscxtip-how-to-determine-the-byte-order-mark-of-a-text-file @@ https://archive.is/RgT42
        # ref: http://poshcode.org/2153 @@ https://archive.is/sGnnu
        $badFiles = @(
            foreach ($file in $files)
            {
                $content = ([char[]](Get-Content $file.FullName -encoding byte -totalcount 3) -join '')
                if ([regex]::match($content, '(?ms)^\xEF\xBB\xBF').success)
                {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following files have utf-8 BOM:`n`n$($badFiles -join "`n")"
        }
    }

    it 'files end with a newline' -skip:$(-not $files_exist) {
        $badFiles = @(
            foreach ($file in $files)
            {
                $string = [System.IO.File]::ReadAllText($file.FullName)
                if ($string.Length -gt 0 -and $string[-1] -ne "`n")
                {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following files do not end with a newline:`n`n$($badFiles -join "`n")"
        }
    }

    it 'file newlines are CRLF' -skip:$(-not $files_exist) {
        $badFiles = @(
            foreach ($file in $files)
            {
                $content = Get-Content -raw $file.FullName
                $lines = [regex]::split($content, '\r\n')
                $lineCount = $lines.Count

                for ($i = 0; $i -lt $lineCount; $i++)
                {
                    if ( [regex]::match($lines[$i], '\r|\n').success )
                    {
                        $file.FullName
                        break
                    }
                }
            }
        )

        if ($badFiles.Count -gt 0)
        {
            throw "The following files have non-CRLF line endings:`n`n$($badFiles -join "`n")"
        }
    }

    it 'files have no lines containing trailing whitespace' -skip:$(-not $files_exist) {
        $badLines = @(
            foreach ($file in $files)
            {
                $lines = [System.IO.File]::ReadAllLines($file.FullName)
                $lineCount = $lines.Count

                for ($i = 0; $i -lt $lineCount; $i++)
                {
                    if ($lines[$i] -match '\s+$')
                    {
                        'File: {0}, Line: {1}' -f $file.FullName, ($i + 1)
                    }
                }
            }
        )

        if ($badLines.Count -gt 0)
        {
            throw "The following $($badLines.Count) lines contain trailing whitespace:`n`n$($badLines -join "`n")"
        }
    }

    it 'any leading whitespace consists only of spaces (excepting makefiles)' -skip:$(-not $files_exist) {
        $badLines = @(
            foreach ($file in $files)
            {
                if ($file.fullname -inotmatch '(^|.)makefile$')
                {
                    $lines = [System.IO.File]::ReadAllLines($file.FullName)
                    $lineCount = $lines.Count

                    for ($i = 0; $i -lt $lineCount; $i++)
                    {
                        if ($lines[$i] -notmatch '^[ ]*(\S|$)')
                        {
                            'File: {0}, Line: {1}' -f $file.FullName, ($i + 1)
                        }
                    }
                }
            }
        )

        if ($badLines.Count -gt 0)
        {
            throw "The following $($badLines.Count) lines contain TABs within leading whitespace:`n`n$($badLines -join "`n")"
        }
    }

}
