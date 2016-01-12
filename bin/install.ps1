#requires -v 3

param(
    [parameter(mandatory=$false)][string] $origin = $null,
    ## NOTE: '_args' is used instead of 'args' to avoid errors due to optimization if/when executed with iex(...)
    [parameter(ValueFromRemainingArguments=$true)][array] $_args = @()
    )

$erroractionpreference='stop' # quit if anything goes wrong

# remote installation instructions (multiple alternatives)
# 1 .. `iex (new-object net.webclient).downloadstring( 'REPO_URL/bin/install.ps1' )`
# 2 .. `'REPO_URL/bin/install.ps1' |%{ iex (new-object net.webclient).downloadstring($_) }`
# 3 .. `'REPO_URL/bin/install.ps1' |%{&$([ScriptBlock]::create((new-object net.webclient).downloadstring($_))) OPTIONAL_ARGS/PARMS}"

# known REPO_URL origin templates
# [BitBucket] REPO_URL == https://bitbucket.org/OWNER/NAME/raw/BRANCH  ## regex == '^https?://[^/]*?(?<domain>bitbucket.org)/(?<owner>[^/]+)/(?<name>[^/]+)/raw/(?<branch>[^/\n]+)'
# [GitHub] REPO_URL == https://raw.github.com/OWNER/NAME/BRANCH  ## regex == '^https?://[^/]*?(?<domain>github.com)/(?<owner>[^/]+)/(?<name>[^/]+)/(?<branch>[^/\n]+)'

# default values
$repo_domain = 'github.com'
$repo_owner = 'rivy'
$repo_name = 'scoop'
$repo_branch = 'master'

# read origin parameter (if supplied)
if ($origin) {
    if ( $($origin -imatch '^https?://[^/]*?(?<domain>bitbucket.org)/(?<owner>[^/]+)/(?<name>[^/]+)/raw/(?<branch>[^/\n]+)') `
     -or $($origin -imatch '^https?://[^/]*?(?<domain>github.com)/(?<owner>[^/]+)/(?<name>[^/]+)/(?<branch>[^/\n]+)')
     )
    {
        $repo_domain = $matches.domain
        $repo_owner = $matches.owner
        $repo_name = $matches.name
        $repo_branch = $matches.branch
    }
}

# build origin URLs
switch -wildcard ($repo_domain) {
    "bitbucket.org" {
        # [Bitbucket]
        # (raw URL format) https://bitbucket.org/OWNER/NAME/raw/BRANCH ...
        $repo_base_raw = "https://$repo_domain/$repo_owner/$repo_name/raw/$repo_branch"
        # (BRANCH.zip URL format) https://bitbucket.org/OWNER/NAME/get/BRANCH.zip
        $repo_branch_zip = "https://$repo_domain/$repo_owner/$repo_name/get/$repo_branch.zip"
        break;
    }
    default { # github.com
        # [GitHub]
        # (raw URL format) https://raw.github.com/OWNER/NAME/BRANCH ...
        $repo_base_raw = "https://raw.$repo_domain/$repo_owner/$repo_name/$repo_branch"
        # (BRANCH.zip URL format) https://github.com/OWNER/NAME/archive/BRANCH.zip
        $repo_branch_zip = "https://$repo_domain/$repo_owner/$repo_name/archive/$repo_branch.zip"
        break;
    }
}

write-host "installing from " -nonewline; write-host "${repo_domain}:${repo_owner}/${repo_name}@${repo_branch}" -f yellow

# get core functions
$core_url = $($repo_base_raw+'/lib/core.ps1')
write-output 'initializing...'
. $( [ScriptBlock]::Create((new-object net.webclient).downloadstring($core_url)) )

# prep
if(installed 'scoop') {
    write-host "scoop is already installed. run 'scoop update' to get the latest version." -f red
    # don't abort if invoked with iex - that would close the PS session
    if($myinvocation.commandorigin -eq 'Internal') { return } else { exit 1 }
}
$dir = ensure (versiondir 'scoop' 'current')

# ensure minimally liberal execution policy
$ep = get-executionpolicy
if (-not ($ep -imatch '^(bypass|unrestricted)$')) {
    write-host 'Default execution policy changed to `' -nonewline; write-host 'unrestricted' -nonewline -f yellow; write-host '`'
    set-executionpolicy unrestricted -scope currentuser
}

# download scoop zip
$zipurl = $repo_branch_zip
$zipfile = "$dir\scoop.zip"
write-output 'downloading...'
dl $zipurl $zipfile

'extracting...'
unzip $zipfile "$dir\_scoop_extract"
copy-item "$dir\_scoop_extract\$repo_name-$repo_branch\*" $dir -r -force
remove-item "$dir\_scoop_extract" -r -force
remove-item $zipfile

write-output 'creating shim...'
shim "$dir\bin\scoop.ps1" $false

ensure_robocopy_in_path
ensure_scoop_in_path
success 'scoop was installed successfully!'
write-output "type ``scoop help`` for instructions"
