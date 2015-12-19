#requires -v 3

# remote install:
#   iex (new-object net.webclient).downloadstring('https://get.scoop.sh')
$erroractionpreference='stop' # quit if anything goes wrong

# get core functions
$core_url = 'https://raw.github.com/lukesampson/scoop/master/lib/core.ps1'
write-output 'initializing...'
invoke-expression (new-object net.webclient).downloadstring($core_url)

# prep
if(installed 'scoop') {
    write-host "scoop is already installed. run 'scoop update' to get the latest version." -f red
    # don't abort if invoked with iex——that would close the PS session
    if($myinvocation.commandorigin -eq 'Internal') { return } else { exit 1 }
}
$dir = ensure (versiondir 'scoop' 'current')

# download scoop zip
$zipurl = 'https://github.com/lukesampson/scoop/archive/master.zip'
$zipfile = "$dir\scoop.zip"
write-output 'downloading...'
dl $zipurl $zipfile

'extracting...'
unzip $zipfile "$dir\_scoop_extract"
copy-item "$dir\_scoop_extract\scoop-master\*" $dir -r -force
remove-item "$dir\_scoop_extract" -r -force
remove-item $zipfile

write-output 'creating shim...'
shim "$dir\bin\scoop.ps1" $false

ensure_robocopy_in_path
ensure_scoop_in_path
success 'scoop was installed successfully!'
write-output "type 'scoop help' for instructions"
