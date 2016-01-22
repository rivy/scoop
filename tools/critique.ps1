
$rule_exclusions = @( 'PSAvoidUsingWriteHost' )

##

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent.FullName

$repo_files = @( Get-ChildItem $repo_dir -file -recurse -force )

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
    $filename = [System.IO.Path]::Combine($repo_dir,"vendor\$lint_module_name\$lint_module_version\$lint_module_name.psd1")
    import-module $(resolve-path $filename)
}
$have_delinter = Get-Module $lint_module_name

if (-not $have_delinter) { throw "unable to find/load '$lint_module_name' for critique"}

foreach ($file in $files) {
    write-host -nonewline "Analyzing '$file' ... "
    Invoke-ScriptAnalyzer $file.FullName -excluderule $rule_exclusions
    write-host "done"
}
