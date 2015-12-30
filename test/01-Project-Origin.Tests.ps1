. "$psscriptroot\..\lib\core.ps1"

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent.FullName

describe 'Project origin' {

    it 'origin defaults are set' {
        @($defaults)             | should not BeNullOrEmpty
        $defaults['repo.domain'] | should not BeNullOrEmpty
        $defaults['repo.owner']  | should not BeNullOrEmpty
        $defaults['repo.name']   | should not BeNullOrEmpty
        $defaults['repo.branch'] | should not BeNullOrEmpty
        $defaults['repo']        | should not BeNullOrEmpty
    }

    $README_text = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo_dir,'.\README.md')))

    it 'README build status badge matches origin defaults' {
        # ex: https://ci.appveyor.com/api/projects/status/jgckhkhe5rdd6586/branch/master?svg=true
        $regex = 'https?://ci.appveyor.com/.*?branch/' + [regex]::escape($defaults['repo.branch'])
        $string = $README_text
        if ( -not ([regex]::match($string, $regex).success) )
        {
            throw "match not found"
        }
    }

    it 'README build link matches origin defaults' {
        # ex: https://ci.appveyor.com/project/rivy/scoop/branch/master
        $regex = 'https?://ci.appveyor.com/project/' + [regex]::escape("$($defaults['repo.owner'])/$($defaults['repo.name'])/branch/$($defaults['repo.branch'])")
        $string = $README_text
        if ( -not ([regex]::match($string, $regex).success) )
        {
            throw "match not found"
        }
    }

    it 'README installation instructions matches origin defaults' {
        # ex: ... 'https://raw.github.com/rivy/scoop/master/bin/install.ps1' |%{&$([ScriptBlock] ...
        $regex = 'https?://.*?' +
            [regex]::escape("$($defaults['repo.domain'])/$($defaults['repo.owner'])/$($defaults['repo.name'])/$($defaults['repo.branch'])/bin/install.ps1") +
            '\s*`|\s*\%\s*\{\s*\&\s*\$\s*\(\s*\[\s*(?i:ScriptBlock)\s*\]'
        $expected_match_count = 2  # CMD and PowerShell instructions
        $string = $README_text
        if ( -not ([regex]::matches($string, $regex).count -ge $expected_match_count) )
        {
            throw "minimum number of matches ($expected_match_count) not found"
        }
    }

    $install_text = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo_dir,'.\bin\install.ps1')))

    it 'bin\install.ps1 defaults match origin defaults' {
        # ex: ...
        # # default values
        # $repo_domain = 'github.com'
        # $repo_owner = 'rivy'
        # $repo_name = 'scoop'
        # $repo_branch = 'master'
        $keys = @( 'domain', 'owner', 'name', 'branch' )
        $string = $install_text
        $bad_keys = @(
            foreach ($key in $keys)
            {
                $k = 'repo.' + $key
                $regex = '(?ms)' + '^\s*\$repo_' + [regex]::escape($key) + '\s*=\s*' + "['`"]" + [regex]::escape($defaults[$k]) + "['`"]" + '\s*$'
                if (-not ([regex]::match($string, $regex).success) )
                {
                    $key
                }
            }
        )

        if ($bad_keys.Count -gt 0)
        {
            throw "The following defaults are missing or do not match:`n$($bad_keys -join "`n")"
        }
    }

}

