write-host -f darkyellow "[$(split-path -leaf $MyInvocation.MyCommand.Path)]"

. "$psscriptroot\..\lib\core.ps1"

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent.FullName

describe 'Project origin' {

    it 'origin defaults are set (from "lib\core.ps1")' {
        @($default)             | should not BeNullOrEmpty
        $default['repo.domain'] | should not BeNullOrEmpty
        $default['repo.owner']  | should not BeNullOrEmpty
        $default['repo.name']   | should not BeNullOrEmpty
        $default['repo.branch'] | should not BeNullOrEmpty
        $default['repo']        | should not BeNullOrEmpty
    }

    it $("origin default branch ('{0}') is either 'master' or matches as a trial release branch" -f $default['repo.branch']) {
        $default['repo.branch'] | should matchExactly ('master|(?:trial|tr)-.*')
    }

    $text = @{}
    $text['README'] = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo_dir,'.\README.md')))
    $text['install'] = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo_dir,'.\bin\install.ps1')))

    it 'README installation instructions matches origin defaults' {
        $expected_match_count = 2  # CMD and PowerShell instructions
        $text = $text['README']
        # ex (alt#1): ... 'https://raw.github.com/rivy/scoop/master/bin/install.ps1' |%{&$([ScriptBlock] ...
        $regex = "'" + 'https?://.*?' +
            [regex]::escape("$($default['repo.domain'])/$($default['repo.owner'])/$($default['repo.name'])/$($default['repo.branch'])/bin/install.ps1") +
            "'" + '\s*`|\s*\%\s*\{\s*\&\s*\$\s*\(\s*\[\s*(?i:ScriptBlock)\s*\]'
        $m = [regex]::matches($text, $regex)
        if (-not $m.sucess) {
            # ex (alt#2): iex (new-object net.webclient).downloadstring( 'https://raw.github.com/rivy/scoop/master/bin/install.ps1' )
            $regex = 'iex\s+\(\s*new-object\s+net\.webclient\)\.downloadstring\s*\(\s*' +
                "'" + 'https?://.*?' +
                [regex]::escape("$($default['repo.domain'])/$($default['repo.owner'])/$($default['repo.name'])/$($default['repo.branch'])/bin/install.ps1") +
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
                $regex = '(?ms)' + '^\s*\$repo_' + [regex]::escape($key) + '\s*=\s*' + "['`"]" + [regex]::escape($default[$k]) + "['`"]" + '\s*$'
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
        $regex = 'https?://ci.appveyor.com/.*?/branch/' + [regex]::escape($default['repo.branch'])
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

    it 'for an origin release branch ~ README build status badge matches origin default' -skip:$(-not ($default['repo.branch'] -match 'master|(?:trial|tr)-.*')) {
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

    $git = try { get-command 'git' -ea stop } catch { $null }
    if ($git) {
        # ref: http://stackoverflow.com/questions/34551805/are-their-names-the-same-a-local-tracking-branch-the-corresponding-remote-trac/34553571#34553571
        # ref: http://stackoverflow.com/questions/21537244/differences-between-git-fetch-and-git-fetch-origin-master/21544585#21544585
        # ref: http://stackoverflow.com/questions/171550/find-out-which-remote-branch-a-local-branch-is-tracking/9753364#9753364
        $current_branch = & "git" @('rev-parse', '--abbrev-ref', 'HEAD')
        if ($current_branch -eq 'HEAD') {
            $current_branch = $null
            # detached HEAD ~ fallback to using for-each-ref/merge-base     ## AppVeyor may test in detached head state from the downloaded branch
            # git >= v2.7.0 ... $b = $(git for-each-ref --count=1 --contains HEAD --sort=-committerdate refs/heads --format=%(refname)) -replace '^refs/heads/', ''
            # ref: http://stackoverflow.com/questions/24993772/how-to-find-all-refs-that-contain-a-commit-in-their-history-in-git/24994211#24994211
            $heads = @( & "git" @('for-each-ref', '--sort=-committerdate', 'refs/heads', '--format=%(refname)') )
            if ($null -ne $heads) { foreach ($head in $heads) {
                if ( $(& "git" @('merge-base', '--is-ancestor', 'HEAD', $head) ; $LASTEXITCODE -eq 0) ) { $current_branch = $head -replace '^refs/heads/', '' }
            }}
        }
        if ($null -ne $current_branch) {
            $current_branch_remote = & "git" @('config', '--get', "branch.${current_branch}.remote")
            $remote = @{}
            if ($null -ne $current_branch_remote) { $remote['url'] = $(& "git" @('config', '--get', "remote.${current_branch_remote}.url")) }
            if ($null -ne $remote['url']) {
                $m = [regex]::match($remote['url'], '.*?[@/](?<domain>[^/:]+)(?:[/:])(?<owner>.+?)/(?<name>.+?)(?:.git)?$')
                if ($m.success) {
                    $remote['domain'] = [string]$m.Groups['domain']
                    $remote['owner'] = [string]$m.Groups['owner']
                    $remote['name'] = [string]$m.Groups['name']
                }
                $remote['branch'] = [string]$(& "git" @('for-each-ref', "--format=%(upstream)", $(& "git" @('symbolic-ref', '-q', 'HEAD')))) -replace "refs/remotes/$current_branch_remote/",''
                foreach ($key in @($remote.keys)) { $remote[$key] = $remote[$key].Trim() }
            }
        }
    }

    # it $("origin default branch ('{0}') is either 'master' or '{1}' (current branch)" -f $default['repo.branch'], $current_branch) -skip:$(-not $current_branch) {
    #     $default['repo.branch'] | should matchExactly ('master|'+[regex]::escape($current_branch))
    # }

    if (($null -ne $remote['url']) -and ($current_branch -match 'master|(?:trial|tr)-.*')) {
        # current branch == published release branch
        it 'for a current, published release branch ~ origin defaults match upstream info' {
            # NOTE: this may need to be relaxed for the 'master' branch if repo is a fork which is based elsewhere
            $keys = @( 'domain', 'owner', 'name', 'branch' )
            $bad_keys = @(
                foreach ($key in $keys)
                {
                    $k = 'repo.' + $key
                    if (-not ($default[$k] -eq $remote[$key]))
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
