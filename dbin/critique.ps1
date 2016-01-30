
$rule_exclusions = @( 'PSAvoidUsingWriteHost' )

##

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent

$repo_files = @( Get-ChildItem $repo_dir.fullname -file -recurse -force )

$project_file_exclusions = @(
    $([regex]::Escape($repo_dir.fullname)+'\\.git\\.*$')
    $([regex]::Escape($repo_dir.fullname)+'\\vendor\\.*$')
)

$files = @(
    $repo_files |
        where-object { $_.fullname -inotmatch $($project_file_exclusions -join '|') } |
        where-object { $_.fullname -imatch '.(ps1|psm1)$' }
)

$files_exist = ($files.Count -gt 0)

if (-not $files_exist) { throw "no files found to critique"}

$lint_module_name = 'PSScriptAnalyzer'
$lint_module_version = '1.3.0'
if (-not (Get-Module $lint_module_name)) {
    $filename = [System.IO.Path]::Combine($repo_dir.fullname,"vendor\$lint_module_name\$lint_module_version\$lint_module_name.psd1")
    import-module $(resolve-path $filename)
}
$have_delinter = Get-Module $lint_module_name

if (-not $have_delinter) { throw "unable to find/load '$lint_module_name' for critique"}

function abbrev_message {
    param([string]$message,[int]$size=$host.ui.RawUI.windowsize.width-1)
    $result = $message
    $continuation = '...'
    $continuation_size = $continuation.length
    if ($message.length -gt $size) { $result = $message.substring(0, $size-$continuation_size) + $continuation }
    $result
}

if ($null -ne $files) { foreach ($file in $files) {
    $repo_relative_name = [System.IO.Path]::Combine(($file.directoryname -replace $('^'+[regex]::escape($repo_dir.fullname)),'.'), $file.name)
    write-host -nonewline "Analyzing $repo_relative_name ... "
    $notes = Invoke-ScriptAnalyzer $file.FullName -excluderule $rule_exclusions
    if ($notes.count -ne 0) {
        write-output ''
        foreach ($note in $notes) {
            if ($note.severity -eq 'information') { write-host -fore cyan $(abbrev_message $("info:(@$($note.line)):'$($note.rulename)': $($note.message)")) }
            if ($note.severity -eq 'warning') { write-host -fore darkyellow $(abbrev_message $("warn:(@$($note.line)):'$($note.rulename)': $($note.message)")) }
            if ($note.severity -eq 'error') { write-host -fore red $(abbrev_message $("err!:(@$($note.line)):'$($note.rulename)': $($note.message)")) }
        }
    } else { write-host -fore green "done" }
}}
