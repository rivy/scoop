#requires -version 2

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
# [jsDelivr] REPO_URL == https://cdn.jsdelivr.net/gh/OWNER/NAME@BRANCH' )" ## regex == '^https?://[^/]*?(?<domain>cdn.jsdelivr.net)/(?<owner>[^/]+)/(?<name>[^/]+)@(?<branch>[^/\n]+)'
# [statically] REPO_URL == https://cdn.statically.io/gh/OWNER/NAME/BRANCH' )" ## regex == '^https?://[^/]*?(?<domain>cdn.statically.io)/(?<owner>[^/]+)/(?<name>[^/]+)/(?<branch>[^/\n]+)'

# default values
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSDeclaredVarsMoreThanAssignments", Target="repo_domain")] ## repo_domain is used by comparison tests of cross-file defaults
$repo_domain = 'github.com'
$repo_owner = 'rivy'
$repo_name = 'scoop'
$repo_branch = 'tr-wip'
$repo_download_base = 'cdn.statically.io/gh'

# read origin parameter (if supplied)
$p = $MyInvocation.MyCommand.Path
write-host "p=$p"
write-host "origin=`"$origin`""
if ($origin) {
    if ( $($origin -imatch '^https?://[^/]*(?<domain>bitbucket.org)/(?<owner>[^/]+)/(?<name>[^/]+)/raw/(?<branch>[^/\n]+)') `
        -or $($origin -imatch '^https?://[^/]*(?<domain>github.com)/(?<owner>[^/]+)/(?<name>[^/]+)/(?<branch>[^/\n]+)') `
        -or $($origin -imatch '^https?://[^/]*(?<domain>cdn.jsdelivr.net/gh)/(?<owner>[^/]+)/(?<name>[^/]+)@(?<branch>[^/\n]+)') `
        -or $($origin -imatch '^https?://[^/]*(?<domain>cdn.statically.io/gh)/(?<owner>[^/]+)/(?<name>[^/]+)/(?<branch>[^/\n]+)')
        )
    {
        $repo_download_base = $matches.domain
        $repo_owner = $matches.owner
        $repo_name = $matches.name
        $repo_branch = $matches.branch
    }
}

# build origin URLs
switch -wildcard ($repo_download_base) {
    "bitbucket.org" {
        # [Bitbucket]
        # (raw URL format) https://bitbucket.org/OWNER/NAME/raw/BRANCH ...
        $repo_base_raw = "https://$repo_download_base/$repo_owner/$repo_name/raw/$repo_branch"
        # (BRANCH.zip URL format) https://bitbucket.org/OWNER/NAME/get/BRANCH.zip
        $repo_branch_zip = "https://$repo_download_base/$repo_owner/$repo_name/get/$repo_branch.zip"
        break;
    }
    "github.com" {
        # [GitHub]
        # (raw/CDN URL format) https://raw.github.com/OWNER/NAME/BRANCH ...
        $repo_base_raw = "https://raw.$repo_download_base/$repo_owner/$repo_name/$repo_branch"
        # (BRANCH.zip URL format) https://github.com/OWNER/NAME/archive/BRANCH.zip
        $repo_branch_zip = "https://$repo_download_base/$repo_owner/$repo_name/archive/$repo_branch.zip"
        break;
    }
    "cdn.jsdelivr.net/gh" {
        # [jsDelivr]
        # (raw/CDN URL format) https://cdn.jsdelivr.net/gh/OWNER/NAME@BRANCH ...
        $repo_base_raw = "https://$repo_download_base/$repo_owner/$repo_name@$repo_branch"
        # (BRANCH.zip URL format) https://github.com/OWNER/NAME/archive/BRANCH.zip
        $repo_branch_zip = "https://github.com/$repo_owner/$repo_name/archive/$repo_branch.zip"
        break;
    }
    default { # "cdn.statically.io/gh"
        # [statically.io]
        # (raw/CDN URL format) https://cdn.statically.io/gh/OWNER/NAME/BRANCH ...
        $repo_base_raw = "https://$repo_download_base/$repo_owner/$repo_name/$repo_branch"
        # (BRANCH.zip URL format) https://github.com/OWNER/NAME/archive/BRANCH.zip
        $repo_branch_zip = "https://github.com/$repo_owner/$repo_name/archive/$repo_branch.zip"
        break;
    }
}

write-host "installing from " -nonewline; write-host "${repo_download_base}:${repo_owner}/${repo_name}@${repo_branch}" -f yellow

# get required functions
# get core functions
write-output 'initializing ...'
$_name = 'lib/core.ps1'
$_url = $($repo_base_raw+'/'+$_name)
write-output "[${_name}] from ${_url} ..."
. $( [ScriptBlock]::Create((new-object net.webclient).downloadstring($_url)) )
## ToDO: ? consolidate required functions for initial installation into `core.ps1`
# get decompress functions ## decompress.ps1 is required `7z` detection and use functions
$_name = 'lib/decompress.ps1'
$_url = $($repo_base_raw+'/'+$_name)
write-output "[${_name}] from ${_url} ..."
. $( [ScriptBlock]::Create((new-object net.webclient).downloadstring($_url)) )
# get install functions ## install.ps1 is required for `curl` downloads
$_name = 'lib/install.ps1'
$_url = $($repo_base_raw+'/'+$_name)
write-output "[${_name}] from ${_url} ..."
. $( [ScriptBlock]::Create((new-object net.webclient).downloadstring($_url)) )
# get version functions ## `installed` from core.ps1 requires versions.ps1
$_name = 'lib/versions.ps1'
$_url = $($repo_base_raw+'/'+$_name)
write-output "[${_name}] from ${_url} ..."
. $( [ScriptBlock]::Create((new-object net.webclient).downloadstring($_url)) )

# prep
# if(installed 'scoop') {
#     write-host "scoop is already installed. run 'scoop update' to get the latest version." -f red
#     # don't abort if invoked with iex - that would close the PS session
#     if ($MyInvocation.MyCommand.CommandType -eq 'Script') { return } else { exit 1 }
# }
$dir = ensure (versiondir 'scoop' 'current')
$projectrootpath = $dir
$projectrootpath = $projectrootpath  ## suppress "defined, not used" message

# ensure minimally liberal execution policy
$ep = get-executionpolicy
if (-not ($ep -imatch '^(bypass|unrestricted)$')) {
    write-host 'Default execution policy changed to `' -nonewline; write-host 'unrestricted' -nonewline -f yellow; write-host '`'
    set-executionpolicy unrestricted -scope currentuser
}

# download `curl`
$bin_dir = ensure "$dir\_bin"
$dl_name = "vendor/curl/curl.exe"
$url = "${repo_base_raw}/${dl_name}"
$file = "${bin_dir}\curl.exe"
write-output "[${dl_name}] from `"${url}`" ..."
dl $url $file
$dl_name = "vendor/curl/curl-ca-bundle.crt"
$url = "${repo_base_raw}/${dl_name}"
$file = "${bin_dir}\ca-bundle.crt"
write-output "[${dl_name}] from `"${url}`" ..."
dl $url $file

# download scoop zip
$zipurl = $repo_branch_zip
$zipfile = "$dir\scoop.zip"
$allow_insecure = $true
$cookies = $null
write-output "[``scoop`` package] from `"${zipurl}`" ..."
dl_progress $zipurl $zipfile $allow_insecure $cookies

'extracting ``scoop`` package archive ...'
unzip $zipfile "$dir\_scoop_extract"
copy-item "$dir\_scoop_extract\$repo_name-*\*" $dir -r -force
remove-item "$dir\_scoop_extract" -r -force
remove-item $zipfile

write-output 'creating shim...'
shim "$dir\bin\scoop.ps1" $false

ensure_robocopy_in_path
ensure_scoop_in_path
success 'scoop was installed successfully!'
write-output "type ``scoop help`` for instructions"
