write-host -f darkyellow "[$(split-path -leaf $MyInvocation.MyCommand.Path)]"

. "$psscriptroot\..\lib\core.ps1"

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent.FullName

describe 'Project origin' {

    it 'origin defaults are set (from "lib\core.ps1")' {
        @($defaults)             | should not BeNullOrEmpty
        $defaults['repo.domain'] | should not BeNullOrEmpty
        $defaults['repo.owner']  | should not BeNullOrEmpty
        $defaults['repo.name']   | should not BeNullOrEmpty
        $defaults['repo.branch'] | should not BeNullOrEmpty
        $defaults['repo']        | should not BeNullOrEmpty
    }

    $git = try { get-command 'git' -ea stop } catch { $null }
    if ($git) {
        # ref: http://stackoverflow.com/questions/34551805/are-their-names-the-same-a-local-tracking-branch-the-corresponding-remote-trac/34553571#34553571
        # ref: http://stackoverflow.com/questions/21537244/differences-between-git-fetch-and-git-fetch-origin-master/21544585#21544585
        # ref: http://stackoverflow.com/questions/171550/find-out-which-remote-branch-a-local-branch-is-tracking/9753364#9753364
        $current_branch = & "git" @('rev-parse', '--abbrev-ref', 'HEAD')
        $current_branch_remote = & "git" @('config', '--get', "branch.${current_branch}.remote")
        $remote = @{}
        if ($null -ne $current_branch_remote) { $remote['url'] = $(& "git" @('config', '--get', "remote.${current_branch_remote}.url")) }
        if ($null -ne $remote['url']) {
            $m = [regex]::match($remote['url'], '.*?[@/](?<domain>.+)(?:[/:])(?<owner>.+?)/(?<name>.+?)(?:.git)?$')
            if ($m.success) {
                $remote['domain'] = $m.Groups['domain']
                $remote['owner'] = $m.Groups['owner']
                $remote['name'] = $m.Groups['name']
            }
            $remote['branch'] = $(& "git" @('for-each-ref', "--format=%(upstream)", $(& "git" @('symbolic-ref', '-q', 'HEAD')))) -replace "refs/remotes/$current_branch_remote/",''
        }
    }

    # it $("origin default branch ('{0}') is either 'master' or '{1}' (current branch)" -f $defaults['repo.branch'], $current_branch) -skip:$(-not $current_branch) {
    #     $defaults['repo.branch'] | should matchExactly ('master|'+[regex]::escape($current_branch))
    # }

    it $("origin default branch ('{0}') is either 'master' or matches as a trial release branch" -f $defaults['repo.branch']) -skip:$(-not $current_branch) {
        $defaults['repo.branch'] | should matchExactly ('master|(?:trial|tr)-.*')
    }

    $text = @{}
    $text['README'] = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo_dir,'.\README.md')))
    $text['install'] = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo_dir,'.\bin\install.ps1')))

    it 'README installation instructions matches origin defaults' {
        $expected_match_count = 2  # CMD and PowerShell instructions
        $text = $text['README']
        # ex (alt#1): ... 'https://raw.github.com/rivy/scoop/master/bin/install.ps1' |%{&$([ScriptBlock] ...
        $regex = "'" + 'https?://.*?' +
            [regex]::escape("$($defaults['repo.domain'])/$($defaults['repo.owner'])/$($defaults['repo.name'])/$($defaults['repo.branch'])/bin/install.ps1") +
            "'" + '\s*`|\s*\%\s*\{\s*\&\s*\$\s*\(\s*\[\s*(?i:ScriptBlock)\s*\]'
        $m = [regex]::matches($text, $regex)
        if (-not $m.sucess) {
            # ex (alt#2): iex (new-object net.webclient).downloadstring( 'https://raw.github.com/rivy/scoop/master/bin/install.ps1' )
            $regex = 'iex\s+\(\s*new-object\s+net\.webclient\)\.downloadstring\s*\(\s*' +
                "'" + 'https?://.*?' +
                [regex]::escape("$($defaults['repo.domain'])/$($defaults['repo.owner'])/$($defaults['repo.name'])/$($defaults['repo.branch'])/bin/install.ps1") +
                "'" + '\s*\)'
            $m = [regex]::matches($text, $regex)
        }
        if (-not ($m.count -ge $expected_match_count))
        {
            throw "minimum number of matches ($expected_match_count) not found"
        }
    }

    it '"bin\install.ps1" defaults match origin defaults' {
        # ex: ...
        # # default values
        # $repo_domain = 'github.com'
        # $repo_owner = 'rivy'
        # $repo_name = 'scoop'
        # $repo_branch = 'master'
        $keys = @( 'domain', 'owner', 'name', 'branch' )
        $text = $text['install']
        $bad_keys = @(
            foreach ($key in $keys)
            {
                $k = 'repo.' + $key
                $regex = '(?ms)' + '^\s*\$repo_' + [regex]::escape($key) + '\s*=\s*' + "['`"]" + [regex]::escape($defaults[$k]) + "['`"]" + '\s*$'
                if (-not ([regex]::match($text, $regex).success))
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

    it 'README build status badge matches origin defaults' {
        # ex: https://ci.appveyor.com/api/projects/status/jgckhkhe5rdd6586/branch/master?svg=true
        $regex = 'https?://ci.appveyor.com/.*?/branch/' + [regex]::escape($defaults['repo.branch'])
        $text = $text['README']
        if (-not ([regex]::match($text, $regex).success))
        {
            throw "match not found"
        }
    }

    it 'README build status badge & link branches are consistent' {
        $text = $text['README']
        # ex (badge): https://ci.appveyor.com/api/projects/status/jgckhkhe5rdd6586/branch/master?svg=true
        $regex = 'https?://ci.appveyor.com/api/projects/status/.*?/branch/(?<branch>[^/?]+)'
        $badge_branch = [regex]::match($text, $regex).Groups['branch'].value
        # ex (link): (https://ci.appveyor.com/project/rivy/scoop/branch/master)
        $regex = '\(\s*https?://ci.appveyor.com/project/.*?/branch/(?<branch>[^/?]+?)\s*\)'
        $link_branch = [regex]::match($text, $regex).Groups['branch'].value
        if (-not ($badge_branch -eq $link_branch))
        {
            throw "Inconsistent badge ('$badge_branch') and link ('$link_branch') branches"
        }
    }

    # release branches == 'master|(?:trial|tr)-.*'

    it 'for an origin release branch ~ README build status badge matches origin default' -skip:$(-not ($defaults['repo.branch'] -match 'master|(?:trial|tr)-.*')) {
        $text = $text['README']
        # ex (badge): https://ci.appveyor.com/api/projects/status/jgckhkhe5rdd6586/branch/master?svg=true
        $regex = 'https?://ci.appveyor.com/api/projects/status/.*?/branch/(?<branch>[^/?]+)'
        $badge_branch = [regex]::match($text, $regex).Groups['branch'].value
        # ex (link): (https://ci.appveyor.com/project/rivy/scoop/branch/master)
        $regex = '\(\s*https?://ci.appveyor.com/project/.*?/branch/(?<branch>[^/?]+?)\s*\)'
        $link_branch = [regex]::match($text, $regex).Groups['branch'].value
        if (-not ($badge_branch -eq $link_branch))
        {
            throw "Inconsistent badge ('$badge_branch') and link ('$link_branch') branches"
        }
    }

    if (($null -ne $remote['url']) -and ($current_branch -match 'master|(?:trial|tr)-.*')) {
        # current branch == published release branch
        it 'for a current, published release branch ~ origin defaults match upstream info' {
            # NOTE: this may need to be relaxed for the 'master' branch if repo is a fork which is based elsewhere
            $keys = @( 'domain', 'owner', 'name', 'branch' )
            $bad_keys = @(
                foreach ($key in $keys)
                {
                    $k = 'repo.' + $key
                    if (-not ($defaults[$k] -eq $remote[$key]))
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

}
